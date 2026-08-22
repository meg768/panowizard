import Foundation
import ImageIO

protocol PanoramaEngine: Sendable {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint]?,
        controlPointsAreAuthoritative: Bool,
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult

    func optimizeControlPoints(
        _ panorama: PanoramaSet,
        controlPoints: [DiagnosticControlPoint],
        controlPointsAreAuthoritative: Bool,
        configuration: StitchingConfiguration
    ) async throws -> ControlPointOptimizationResult
}

struct PanoramaStitchResult: Sendable {
    let url: URL?
    let rigImageLines: [UUID: String]
    let nadirRepair: NadirRepairRegistrationResult?
    let zenithRepair: NadirRepairRegistrationResult?
    let controlPointDiagnostics: ControlPointDiagnostics?
}

struct ControlPointOptimizationResult: Sendable {
    let diagnostics: ControlPointDiagnostics
}

enum PanoramaEngineError: LocalizedError {
    case insufficientImages
    case stitchingFailed(String)
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .insufficientImages:
            "Minst två bilder krävs för sammanfogning."
        case .stitchingFailed(let message):
            message
        case .notInstalled:
            "Den nya stitchmotorn byggs separat och är inte inkopplad ännu."
        }
    }
}

struct HuginOpenCVPanoramaEngine: PanoramaEngine {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint]?,
        controlPointsAreAuthoritative: Bool,
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.stitchSynchronously(
                panorama,
                masks: masks,
                protectedMasks: protectedMasks,
                controlPoints: controlPoints,
                controlPointsAreAuthoritative: controlPointsAreAuthoritative,
                configuration: configuration,
                rendersPanorama: true
            )
        }.value
    }

    func optimizeControlPoints(
        _ panorama: PanoramaSet,
        controlPoints: [DiagnosticControlPoint],
        controlPointsAreAuthoritative: Bool,
        configuration: StitchingConfiguration
    ) async throws -> ControlPointOptimizationResult {
        try await Task.detached(priority: .userInitiated) {
            let result = try Self.stitchSynchronously(
                panorama,
                masks: [:],
                protectedMasks: [:],
                controlPoints: controlPoints,
                controlPointsAreAuthoritative: controlPointsAreAuthoritative,
                configuration: configuration,
                rendersPanorama: false
            )
            guard let diagnostics = result.controlPointDiagnostics else {
                throw PanoramaEngineError.stitchingFailed(
                    "Hugin returnerade inga kontrollpunktsdata."
                )
            }
            return ControlPointOptimizationResult(diagnostics: diagnostics)
        }.value
    }

    private static func stitchSynchronously(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint]?,
        controlPointsAreAuthoritative: Bool,
        configuration: StitchingConfiguration,
        rendersPanorama: Bool,
        automaticStabilizationAttempt: Int = 0
    ) throws -> PanoramaStitchResult {
        let enabledImages = panorama.images.filter(\.isEnabled)
        let alignmentImages = enabledImages.filter { $0.role == .alignment }
        let fillOnlyImages = enabledImages.filter { $0.role == .fillOnly }
        // Every positioning image belongs to the same globally optimized rig.
        // Direction is retained only as a repair target for old project files.
        let ringImages = alignmentImages
        let nadirRepairImages = fillOnlyImages.filter {
            $0.direction != .zenith
        }
        let zenithRepairImages = fillOnlyImages.filter { $0.direction == .zenith }

        guard ringImages.count >= 2 else {
            throw PanoramaEngineError.insufficientImages
        }
        guard nadirRepairImages.count <= 1 else {
            throw PanoramaEngineError.stitchingFailed(
                duplicateRepairMessage(
                    direction: .nadir,
                    repairs: nadirRepairImages,
                    allImages: panorama.images
                )
            )
        }
        guard zenithRepairImages.count <= 1 else {
            throw PanoramaEngineError.stitchingFailed(
                duplicateRepairMessage(
                    direction: .zenith,
                    repairs: zenithRepairImages,
                    allImages: panorama.images
                )
            )
        }

        let toolchain = try HuginToolchain.live()
        let workDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/Stitches/\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: workDirectory)
        }

        let geometryDirectory = workDirectory.appending(
            path: "geometry-sources",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: geometryDirectory,
            withIntermediateDirectories: true
        )
        let geometryInputs = ringImages
        let geometryImages = try geometryInputs.enumerated().map { index, image in
            let destination = geometryDirectory.appending(
                path: "source-\(index).tif"
            )
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: nil,
                clipsToFisheyeCircle: false,
                sourceFisheyeFactor: configuration.lensProfile == .sigma8DX
                    ? -0.526971 : nil,
                destinationURL: destination
            )
            return Self.replacingURL(of: image, with: destination)
        }
        let geometryByID = Dictionary(
            uniqueKeysWithValues: geometryImages.map { ($0.id, $0) }
        )
        let geometryRingImages = ringImages.map { geometryByID[$0.id] ?? $0 }

        let horizontalFieldOfView = initialFieldOfView(
            configuration,
            images: ringImages
        )
        let baseProject = workDirectory.appending(path: "01-base.pto")
        let seededProject = workDirectory.appending(path: "02-seeded.pto")
        let controlPointProject = workDirectory.appending(path: "03-points.pto")
        let poseInputProject = workDirectory.appending(path: "04-pose-input.pto")
        let plausibleRingProject = workDirectory.appending(
            path: "03-plausible-pairs.pto"
        )
        let ringBackboneProject = workDirectory.appending(
            path: "03-ring-backbone.pto"
        )
        let poseProject = workDirectory.appending(path: "05-pose.pto")
        let cleanedRingProject = workDirectory.appending(path: "04-cleaned.pto")
        let lensInputProject = workDirectory.appending(path: "05-lens-input.pto")
        let optimizedRingProject = workDirectory.appending(path: "05-ring.pto")
        let robustRingProject = workDirectory.appending(path: "05-ring-robust.pto")
        let robustInputProject = workDirectory.appending(
            path: "05-ring-robust-input.pto"
        )
        let isCircularFisheye = configuration.lensProfile == .sigma8DX
        let isNikon105 = configuration.lensProfile == .nikon105DX
        let usesCalibratedFisheye = isCircularFisheye || isNikon105

        log("Ring feature matching", images: ringImages)
        let matchingFieldOfView = isCircularFisheye
            ? configuration.lensProfile.defaultHorizontalFieldOfView
                ?? horizontalFieldOfView
            : horizontalFieldOfView
        var generatorArguments = [
            "-p", isCircularFisheye ? "2" : "3",
            "-f", String(matchingFieldOfView)
        ]
        generatorArguments += [
            "-o", baseProject.path(percentEncoded: false)
        ]
        try toolchain.run(
            "pto_gen",
            arguments: generatorArguments + geometryRingImages.map {
                $0.url.path(percentEncoded: false)
            },
            in: workDirectory
        )
        try HuginProjectFile.seedRing(
            from: baseProject,
            to: seededProject,
            imageCount: ringImages.count
        )
        if isCircularFisheye {
            try HuginProjectFile.configuringRingOptimization(
                in: seededProject,
                imageCount: ringImages.count
            )
        } else if isNikon105 {
            try HuginProjectFile.configuringNikon105RingOptimization(
                in: seededProject,
                imageCount: ringImages.count,
                horizontalFieldOfView: horizontalFieldOfView
            )
        }
        let ringIndexByID = Dictionary(uniqueKeysWithValues:
            ringImages.enumerated().map { ($0.element.id, $0.offset) }
        )
        let editedRingEntries = controlPoints?.compactMap {
            point -> (point: PanoramaControlPoint, id: UUID)? in
            guard panorama.images.indices.contains(point.firstImage),
                  panorama.images.indices.contains(point.secondImage),
                  let first = ringIndexByID[
                    panorama.images[point.firstImage].id
                  ],
                  let second = ringIndexByID[
                    panorama.images[point.secondImage].id
                  ] else { return nil }
            let firstPoint = configuration.lensProfile == .sigma8DX
                ? Self.remappingFisheyePoint(
                    x: point.firstX, y: point.firstY,
                    width: ringImages[first].pixelWidth,
                    height: ringImages[first].pixelHeight,
                    sourceFactor: -0.526971, destinationFactor: -0.5
                ) : (point.firstX, point.firstY)
            let secondPoint = configuration.lensProfile == .sigma8DX
                ? Self.remappingFisheyePoint(
                    x: point.secondX, y: point.secondY,
                    width: ringImages[second].pixelWidth,
                    height: ringImages[second].pixelHeight,
                    sourceFactor: -0.526971, destinationFactor: -0.5
                ) : (point.secondX, point.secondY)
            return (
                PanoramaControlPoint(
                    firstImage: first, secondImage: second,
                    firstX: firstPoint.0, firstY: firstPoint.1,
                    secondX: secondPoint.0, secondY: secondPoint.1
                ),
                point.id
            )
        }
        let editedRingPoints = editedRingEntries?.map(\.point)
        let editedRingPointIDs = editedRingEntries?.map(\.id) ?? []
        let hasSuppliedControlPoints = editedRingPoints?.isEmpty == false
        let usesEditedControlPoints = Self.treatsSuppliedControlPointsAsEdited(
            hasSuppliedControlPoints: hasSuppliedControlPoints,
            controlPointsAreAuthoritative: controlPointsAreAuthoritative,
            automaticStabilizationAttempt: automaticStabilizationAttempt
        )
        let ringControlPoints: [PanoramaControlPoint]
        if hasSuppliedControlPoints {
            ringControlPoints = editedRingPoints!
        } else {
            let generatedPoints = try OpenCVControlPointMatcher.ring(
                images: ringImages,
                horizontalFieldOfView: matchingFieldOfView,
                lensProfile: configuration.lensProfile
            )
            ringControlPoints = isCircularFisheye
                ? generatedPoints.map { point in
                    let first = Self.remappingFisheyePoint(
                        x: point.firstX, y: point.firstY,
                        width: ringImages[point.firstImage].pixelWidth,
                        height: ringImages[point.firstImage].pixelHeight,
                        sourceFactor: -0.526971, destinationFactor: -0.5
                    )
                    let second = Self.remappingFisheyePoint(
                        x: point.secondX, y: point.secondY,
                        width: ringImages[point.secondImage].pixelWidth,
                        height: ringImages[point.secondImage].pixelHeight,
                        sourceFactor: -0.526971, destinationFactor: -0.5
                    )
                    return PanoramaControlPoint(
                        firstImage: point.firstImage,
                        secondImage: point.secondImage,
                        firstX: first.0,
                        firstY: first.1,
                        secondX: second.0,
                        secondY: second.1
                    )
                } : generatedPoints
        }
        let usesSparseRing = automaticStabilizationAttempt == 0
            && !usesEditedControlPoints
            && usesCalibratedFisheye
            && OpenCVControlPointMatcher.needsSparseCycleProtection(
                in: OpenCVControlPointMatcher.lastPairDiagnostics
            )
        if !usesEditedControlPoints {
            for diagnostic in OpenCVControlPointMatcher.lastPairDiagnostics {
                print(
                    "[PanoWizard] CP pair "
                        + "\(diagnostic.firstImage)-\(diagnostic.secondImage): "
                        + "features=\(diagnostic.firstFeatureCount)/"
                        + "\(diagnostic.secondFeatureCount) "
                        + "ratio=\(diagnostic.ratioMatchCount) "
                        + "mutual=\(diagnostic.mutualMatchCount) "
                        + "geometric=\(diagnostic.geometricMatchCount) "
                        + "selected=\(diagnostic.selectedControlPointCount) "
                        + "coverage="
                        + String(format: "%.3f", diagnostic.spatialCoverage)
                )
            }
        }
        try HuginProjectFile.appending(
            controlPoints: ringControlPoints,
            from: seededProject,
            to: controlPointProject
        )
        if usesCalibratedFisheye {
            let nominalYaws = try HuginProjectFile.inferredRingYaws(
                in: controlPointProject,
                imageCount: ringImages.count
            )
            if usesEditedControlPoints {
                // A manual/imported CP set is the experiment's input. Do not
                // silently discard pairs or reduce it to PanoWizard's
                // automatically selected ring backbone.
                try FileManager.default.copyItem(
                    at: controlPointProject,
                    to: ringBackboneProject
                )
            } else {
                if preservesSuppliedRingGraph(
                    hasSuppliedControlPoints: hasSuppliedControlPoints,
                    isCircularFisheye: isCircularFisheye
                ) {
                    // The app's wizard has already generated and saved one
                    // connected graph. Do not reinterpret that same graph as
                    // camera-direction groups and reduce it a second time:
                    // duplicate or strongly pitched views can otherwise be
                    // isolated even though explicit bridge points exist.
                    // Internally generated Sigma rings also keep their dense
                    // redundant graph for lens and optical-centre refinement.
                    // Automatic points are still cleaned by cpclean and the
                    // robust residual pass below.
                    try FileManager.default.copyItem(
                        at: controlPointProject,
                        to: ringBackboneProject
                    )
                } else {
                    // Repeated exposures from the same direction make a dense
                    // fisheye graph poorly conditioned. Keep their internal
                    // constraints, but solve the ring through one well-linked
                    // representative per detected camera direction.
                    try HuginProjectFile.filteringImplausibleRingPairs(
                        from: controlPointProject,
                        to: plausibleRingProject,
                        nominalYaws: nominalYaws
                    )
                    try HuginProjectFile.filteringToRingBackbone(
                        from: plausibleRingProject,
                        to: ringBackboneProject,
                        nominalYaws: nominalYaws
                    )
                }
            }
            if isCircularFisheye {
                try HuginProjectFile.configuringSigmaPoseOptimization(
                    from: ringBackboneProject,
                    to: poseInputProject,
                    nominalYaws: nominalYaws,
                    horizontalFieldOfView: horizontalFieldOfView
                )
            } else {
                try HuginProjectFile.configuringNikon105PoseOptimization(
                    from: ringBackboneProject,
                    to: poseInputProject,
                    nominalYaws: nominalYaws,
                    horizontalFieldOfView: horizontalFieldOfView
                )
            }
            try toolchain.run(
                "autooptimiser",
                arguments: [
                    "-n",
                    "-o", poseProject.path(percentEncoded: false),
                    poseInputProject.path(percentEncoded: false)
                ],
                in: workDirectory
            )
        } else {
            try FileManager.default.copyItem(
                at: controlPointProject,
                to: poseProject
            )
        }

        log("Ring bundle adjustment", images: ringImages)
        if usesEditedControlPoints || usesSparseRing
            || isCircularFisheye {
            // cpclean evaluates the pose before Sigma's lens and optical
            // centre have been refined. It therefore mistakes useful polar
            // constraints for outliers. Preserve them through the first lens
            // solve; the robust residual pass below still rejects individual
            // inconsistent points. Edited points remain untouched.
            try FileManager.default.copyItem(
                at: poseProject,
                to: cleanedRingProject
            )
        } else {
            try toolchain.run(
                "cpclean",
                arguments: [
                    "-o", cleanedRingProject.path(percentEncoded: false),
                    poseProject.path(percentEncoded: false)
                ],
                in: workDirectory
            )
        }
        if isCircularFisheye {
            try HuginProjectFile.configuringSigmaLensRefinement(
                from: cleanedRingProject,
                to: lensInputProject
            )
        } else if isNikon105 {
            try HuginProjectFile.configuringNikon105LensRefinement(
                from: cleanedRingProject,
                to: lensInputProject
            )
        } else {
            try FileManager.default.copyItem(
                at: cleanedRingProject,
                to: lensInputProject
            )
        }
        try toolchain.run(
            "autooptimiser",
            arguments: [
                "-n",
                "-l",
                "-o", optimizedRingProject.path(percentEncoded: false),
                lensInputProject.path(percentEncoded: false)
            ],
            in: workDirectory
        )
        var finalOptimizedRingProject = optimizedRingProject
        let initiallyOptimizedPoints = try HuginProjectFile.controlPoints(
            in: optimizedRingProject
        )
        let initiallyOptimizedErrors = try toolchain.controlPointErrors(
            in: optimizedRingProject,
            points: initiallyOptimizedPoints
        )
        let acceptedPoints = robustControlPoints(
            initiallyOptimizedPoints,
            errors: initiallyOptimizedErrors
        )
        if !usesEditedControlPoints,
           !usesSparseRing,
           acceptedPoints.count < initiallyOptimizedPoints.count {
            let filteredProject = workDirectory.appending(
                path: "05-ring-outliers-removed.pto"
            )
            try HuginProjectFile.filteringControlPoints(
                from: isCircularFisheye
                    ? ringBackboneProject : optimizedRingProject,
                to: filteredProject
            ) { point in
                acceptedPoints.contains { accepted in
                    accepted.firstImage == point.firstImage
                        && accepted.secondImage == point.secondImage
                        && abs(accepted.firstX - point.firstX) < 0.01
                        && abs(accepted.firstY - point.firstY) < 0.01
                        && abs(accepted.secondX - point.secondX) < 0.01
                        && abs(accepted.secondY - point.secondY) < 0.01
                }
            }
            if isCircularFisheye {
                // A contradictory dense graph can collapse the first lens
                // solve. Restart from the inferred camera directions after
                // residual filtering; never inherit that collapsed pose.
                let restartPoseInput = workDirectory.appending(
                    path: "05-ring-restart-pose-input.pto"
                )
                let restartPose = workDirectory.appending(
                    path: "05-ring-restart-pose.pto"
                )
                // Re-infer directions from the surviving graph. A weak false
                // pair may have merged two real camera directions in the raw
                // graph; reusing those stale nominal yaws is exactly what made
                // Panorama C require a second click to reach the good pose.
                let restartYaws = try HuginProjectFile.inferredRingYaws(
                    in: filteredProject,
                    imageCount: ringImages.count
                )
                try HuginProjectFile.configuringSigmaPoseOptimization(
                    from: filteredProject,
                    to: restartPoseInput,
                    nominalYaws: restartYaws,
                    horizontalFieldOfView: horizontalFieldOfView
                )
                try toolchain.run(
                    "autooptimiser",
                    arguments: [
                        "-n", "-o", restartPose.path(percentEncoded: false),
                        restartPoseInput.path(percentEncoded: false)
                    ],
                    in: workDirectory
                )
                try HuginProjectFile.configuringSigmaLensRefinement(
                    from: restartPose,
                    to: robustInputProject
                )
                try toolchain.run(
                    "autooptimiser",
                    arguments: [
                        "-n", "-l",
                        "-o", robustRingProject.path(percentEncoded: false),
                        robustInputProject.path(percentEncoded: false)
                    ],
                    in: workDirectory
                )
            } else {
                // Keep the already solved lens fixed here. Releasing lens and
                // pose together after removing outliers can find a numerically
                // low-error but visually degenerate fisheye solution.
                try HuginProjectFile.configuringPoseRefinement(
                    from: filteredProject,
                    to: robustInputProject
                )
                try toolchain.run(
                    "autooptimiser",
                    arguments: [
                        "-n",
                        "-o", robustRingProject.path(percentEncoded: false),
                        robustInputProject.path(percentEncoded: false)
                    ],
                    in: workDirectory
                )
            }
            finalOptimizedRingProject = robustRingProject
        }
        if !usesEditedControlPoints, !usesSparseRing {
            // The first robust pass can recover a solution that was badly
            // displaced by one false pair. Re-evaluate once in that recovered
            // geometry so isolated residual outliers do not survive merely
            // because the initial model itself was poor.
            let refinedPoints = try HuginProjectFile.controlPoints(
                in: finalOptimizedRingProject
            )
            let refinedErrors = try toolchain.controlPointErrors(
                in: finalOptimizedRingProject,
                points: refinedPoints
            )
            let twiceAcceptedPoints = robustControlPoints(
                refinedPoints,
                errors: refinedErrors
            )
            if twiceAcceptedPoints.count < refinedPoints.count {
                let twiceFilteredProject = workDirectory.appending(
                    path: "05-ring-second-outliers-removed.pto"
                )
                let twiceRobustInputProject = workDirectory.appending(
                    path: "05-ring-second-robust-input.pto"
                )
                let twiceRobustProject = workDirectory.appending(
                    path: "05-ring-second-robust.pto"
                )
                try HuginProjectFile.filteringControlPoints(
                    from: finalOptimizedRingProject,
                    to: twiceFilteredProject
                ) { point in
                    twiceAcceptedPoints.contains { accepted in
                        accepted.firstImage == point.firstImage
                            && accepted.secondImage == point.secondImage
                            && abs(accepted.firstX - point.firstX) < 0.01
                            && abs(accepted.firstY - point.firstY) < 0.01
                            && abs(accepted.secondX - point.secondX) < 0.01
                            && abs(accepted.secondY - point.secondY) < 0.01
                    }
                }
                try HuginProjectFile.configuringPoseRefinement(
                    from: twiceFilteredProject,
                    to: twiceRobustInputProject
                )
                try toolchain.run(
                    "autooptimiser",
                    arguments: [
                        "-n", "-o",
                        twiceRobustProject.path(percentEncoded: false),
                        twiceRobustInputProject.path(percentEncoded: false)
                    ],
                    in: workDirectory
                )
                finalOptimizedRingProject = twiceRobustProject
            }
        }
        var cleanedDiagnosticPoints: [DiagnosticControlPoint]
        if usesEditedControlPoints, let editedRingPoints {
            cleanedDiagnosticPoints = zip(
                editedRingPoints,
                editedRingPointIDs
            ).map { point, id in
                DiagnosticControlPoint(
                    id: id,
                    firstImage: point.firstImage,
                    secondImage: point.secondImage,
                    firstX: point.firstX,
                    firstY: point.firstY,
                    secondX: point.secondX,
                    secondY: point.secondY
                )
            }
        } else {
            cleanedDiagnosticPoints = try HuginProjectFile.controlPoints(
                in: finalOptimizedRingProject
            )
        }
        let pointErrors = try toolchain.controlPointErrors(
            in: finalOptimizedRingProject,
            points: cleanedDiagnosticPoints
        )
        for index in cleanedDiagnosticPoints.indices {
            let parsed = cleanedDiagnosticPoints[index]
            cleanedDiagnosticPoints[index] = DiagnosticControlPoint(
                id: editedRingPointIDs.indices.contains(index)
                    ? editedRingPointIDs[index] : parsed.id,
                firstImage: parsed.firstImage,
                secondImage: parsed.secondImage,
                firstX: parsed.firstX,
                firstY: parsed.firstY,
                secondX: parsed.secondX,
                secondY: parsed.secondY,
                error: pointErrors[index]
            )
        }
        let panoramaIndexByID = Dictionary(uniqueKeysWithValues:
            panorama.images.enumerated().map { ($0.element.id, $0.offset) }
        )
        let ringPointsInPanorama = cleanedDiagnosticPoints.compactMap {
            point -> DiagnosticControlPoint? in
            guard ringImages.indices.contains(point.firstImage),
                  ringImages.indices.contains(point.secondImage),
                  let first = panoramaIndexByID[ringImages[point.firstImage].id],
                  let second = panoramaIndexByID[ringImages[point.secondImage].id]
            else { return nil }
            let firstPoint = isCircularFisheye
                ? Self.remappingFisheyePoint(
                    x: point.firstX, y: point.firstY,
                    width: ringImages[point.firstImage].pixelWidth,
                    height: ringImages[point.firstImage].pixelHeight,
                    sourceFactor: -0.5, destinationFactor: -0.526971
                ) : (point.firstX, point.firstY)
            let secondPoint = isCircularFisheye
                ? Self.remappingFisheyePoint(
                    x: point.secondX, y: point.secondY,
                    width: ringImages[point.secondImage].pixelWidth,
                    height: ringImages[point.secondImage].pixelHeight,
                    sourceFactor: -0.5, destinationFactor: -0.526971
                ) : (point.secondX, point.secondY)
            return DiagnosticControlPoint(
                id: point.id,
                firstImage: first,
                secondImage: second,
                firstX: firstPoint.0,
                firstY: firstPoint.1,
                secondX: secondPoint.0,
                secondY: secondPoint.1,
                error: point.error
            )
        }
        let diagnosticPoints = ringPointsInPanorama
        let controlPointDiagnostics = ControlPointDiagnostics(
            images: panorama.images,
            rawPoints: controlPoints ?? diagnosticPoints,
            cleanedPoints: diagnosticPoints
        )
        let automaticGeometryIsUnstable = Self.needsAutomaticStabilization(
            errors: diagnosticPoints.compactMap(\.error)
        )
        if automaticGeometryIsUnstable {
            let finiteErrors = diagnosticPoints.compactMap(\.error)
                .filter(\.isFinite)
                .sorted()
            let median = finiteErrors[finiteErrors.count / 2]
            let p90 = finiteErrors[min(
                finiteErrors.count - 1,
                Int(Double(finiteErrors.count) * 0.9)
            )]
            print(
                "[PanoWizard] Unstable automatic geometry "
                    + "attempt=\(automaticStabilizationAttempt) "
                    + "sparseRing=\(usesSparseRing) "
                    + "edited=\(usesEditedControlPoints) "
                    + "points=\(finiteErrors.count) "
                    + String(
                        format: "median=%.3f p90=%.3f max=%.3f",
                        median, p90, finiteErrors.last ?? 0
                    )
            )
            let errorsByPair = Dictionary(grouping: diagnosticPoints) { $0.pair }
            for pair in errorsByPair.keys.sorted(by: {
                ($0.firstImage, $0.secondImage)
                    < ($1.firstImage, $1.secondImage)
            }) {
                let pairErrors = errorsByPair[pair, default: []]
                    .compactMap(\.error).filter(\.isFinite).sorted()
                guard !pairErrors.isEmpty else { continue }
                print(
                    "[PanoWizard] Residual pair "
                        + "\(pair.firstImage)-\(pair.secondImage): "
                        + "count=\(pairErrors.count) "
                        + String(
                            format: "median=%.3f max=%.3f",
                            pairErrors[pairErrors.count / 2],
                            pairErrors.last ?? 0
                        )
                )
            }
        }
        if automaticStabilizationAttempt > 0 && automaticGeometryIsUnstable {
            // The points on this pass are marked authoritative only so the
            // internal recovery pass cannot silently replace them. They are
            // still machine-generated, so a second bad solve must never be
            // rendered and mistaken for a completed panorama.
            throw PanoramaEngineError.stitchingFailed(
                "Den automatiska geometrin kunde inte stabiliseras. "
                    + "Panoramat skapades inte, eftersom resultatet annars "
                    + "skulle bli felplacerat eller nästan helt svart."
            )
        }
        if !controlPointsAreAuthoritative && automaticGeometryIsUnstable {
            // A badly displaced first Sigma solve can remain in the wrong
            // local minimum even after its false pairs have been removed.
            // Starting once more from that cleaned graph is equivalent to the
            // user's previously necessary second click, but happens before a
            // bad panorama is ever returned or saved.
            print(
                "[PanoWizard] Re-running the cleaned automatic CP graph "
                    + "to stabilize the recovered geometry"
            )
            return try stitchSynchronously(
                panorama,
                masks: masks,
                protectedMasks: protectedMasks,
                controlPoints: diagnosticPoints,
                controlPointsAreAuthoritative: true,
                configuration: configuration,
                rendersPanorama: rendersPanorama,
                automaticStabilizationAttempt: automaticStabilizationAttempt + 1
            )
        }
        if !rendersPanorama {
            return PanoramaStitchResult(
                url: nil,
                rigImageLines: [:],
                nadirRepair: nil,
                zenithRepair: nil,
                controlPointDiagnostics: controlPointDiagnostics
            )
        }

        var ringGeometryProject = finalOptimizedRingProject
        var ringOrientations = try HuginProjectFile.orientations(
            in: ringGeometryProject
        )
        if Self.needsUprightCanonicalization(
            orientations: ringOrientations
        ) {
            let uprightProject = workDirectory.appending(
                path: "05-ring-upright.pto"
            )
            try toolchain.run(
                "pano_modify",
                arguments: [
                    "-o", uprightProject.path(percentEncoded: false),
                    "--rotate=0,0,180",
                    ringGeometryProject.path(percentEncoded: false)
                ],
                in: workDirectory
            )
            ringGeometryProject = uprightProject
            ringOrientations = try HuginProjectFile.orientations(
                in: ringGeometryProject
            )
        }
        print("[PanoWizard] Ring orientations: " + ringOrientations
            .enumerated().map { index, orientation in
                "\(index):y=\(String(format: "%.2f", orientation.yaw)) "
                    + "p=\(String(format: "%.2f", orientation.pitch)) "
                    + "r=\(String(format: "%.2f", orientation.roll))"
            }.joined(separator: ", "))
        let disconnectedComponents = Self.controlPointComponents(
            imageCount: ringImages.count,
            controlPoints: cleanedDiagnosticPoints
        )
        if disconnectedComponents.count > 1 {
            let groups = disconnectedComponents.map { component in
                Self.projectImageNumbers(
                    for: component,
                    ringImages: ringImages,
                    panoramaImages: panorama.images
                ).map(String.init).joined(separator: ", ")
            }.joined(separator: " | ")
            throw PanoramaEngineError.stitchingFailed(
                "Kontrollpunktsnätet är uppdelat i separata bildgrupper: "
                    + "\(groups). Aktivera en bryggbild eller lägg till "
                    + "kontrollpunkter mellan två bilder som faktiskt överlappar."
            )
        }
        if usesCalibratedFisheye,
           ringImages.count >= 3,
           !Self.hasReliable360DegreeBackbone(
               orientations: ringOrientations,
               horizontalFieldOfView: matchingFieldOfView,
               controlPoints: cleanedDiagnosticPoints,
               logsDiagnostics: true
           ) {
            throw PanoramaEngineError.stitchingFailed(
                "Kontrollpunktsnätet saknar en tillförlitlig sluten "
                    + "360°-stomme. Den automatiska geometrin avbröts "
                    + "i stället för att skapa en öppen eller vikt ring."
            )
        }
        let finalGeometryProject = ringGeometryProject
        let orderedImages = ringImages

        log("Warp and blend", images: orderedImages)
        let preparedDirectory = workDirectory.appending(
            path: "prepared",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: preparedDirectory,
            withIntermediateDirectories: true
        )
        let clipsToCircle = configuration.lensProfile == .sigma8DX
        let preparedImages = try orderedImages.enumerated().map { index, image in
            let destination = preparedDirectory.appending(
                path: "source-\(index).tif"
            )
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: masks[image.id],
                clipsToFisheyeCircle: clipsToCircle,
                sourceFisheyeFactor: isCircularFisheye ? -0.526971 : nil,
                destinationURL: destination
            )
            return destination
        }
        let renderSourcesProject = workDirectory.appending(
            path: "09-render-sources.pto"
        )
        let photometricProject = workDirectory.appending(
            path: "09-photometric.pto"
        )
        var renderGeometryProject = finalGeometryProject
        do {
            // Geometry and control points are already final. Match exposure,
            // white balance and vignetting before Nona creates the layers so
            // Enblend does not have to hide a broad brightness discontinuity
            // at the edge of a hand-painted exclusion mask.
            try toolchain.run(
                "autooptimiser",
                arguments: [
                    "-m",
                    "-o", photometricProject.path(percentEncoded: false),
                    finalGeometryProject.path(percentEncoded: false)
                ],
                in: workDirectory
            )
            renderGeometryProject = photometricProject
        } catch {
            // Photometric matching improves difficult seams but must never
            // prevent an otherwise valid panorama from rendering.
            log(
                "Photometric matching skipped: \(error.localizedDescription)",
                images: orderedImages
            )
        }
        let seamCenteredProject = workDirectory.appending(
            path: "09-seam-centered.pto"
        )
        try HuginProjectFile.centeringPanoramaSeamBetweenRingImages(
            from: renderGeometryProject,
            to: seamCenteredProject,
            ringImageCount: ringImages.count
        )
        try HuginProjectFile.replacingImagePaths(
            in: seamCenteredProject,
            with: preparedImages,
            destination: renderSourcesProject
        )
        let renderProject = workDirectory.appending(path: "10-render.pto")
        try toolchain.run(
            "pano_modify",
            arguments: [
                "-o", renderProject.path(percentEncoded: false),
                "-p", "2",
                "--fov=360x180",
                "--canvas=4000x2000",
                "--blender=ENBLEND",
                "--ldr-file=JPG",
                "--ldr-compression=92",
                renderSourcesProject.path(percentEncoded: false)
            ],
            in: workDirectory
        )
        let layerPrefix = workDirectory.appending(path: "layer")
        try toolchain.run(
            "nona",
            arguments: [
                "-r", "ldr",
                "-m", "TIFF_m",
                "-o", layerPrefix.path(percentEncoded: false),
                renderProject.path(percentEncoded: false)
            ],
            in: workDirectory
        )
        let layers = try FileManager.default.contentsOfDirectory(
            at: workDirectory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("layer")
                && ["tif", "tiff"].contains($0.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !layers.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "Hugin skapade inga bildlager."
            )
        }
        var blendLayers = layers
        let protectedIndices = orderedImages.indices.filter {
            protectedMasks[orderedImages[$0].id] != nil
        }
        if !protectedIndices.isEmpty {
            var protectedPreparedImages = preparedImages
            for index in protectedIndices {
                let image = orderedImages[index]
                guard let protectedMask = protectedMasks[image.id],
                      let outsideProtected = SourceMaskRasterizer.inverted(
                        protectedMask,
                        width: image.pixelWidth,
                        height: image.pixelHeight,
                        protectedArea: true
                      ) else { continue }
                let destination = preparedDirectory.appending(
                    path: "protected-source-\(index).tif"
                )
                try MaskedSourceImageWriter.write(
                    sourceURL: image.url,
                    maskData: outsideProtected,
                    clipsToFisheyeCircle: clipsToCircle,
                    sourceFisheyeFactor: isCircularFisheye ? -0.526971 : nil,
                    destinationURL: destination
                )
                protectedPreparedImages[index] = destination
            }

            let protectedProject = workDirectory.appending(
                path: "10-protected-render.pto"
            )
            try HuginProjectFile.replacingImagePaths(
                in: renderProject,
                with: protectedPreparedImages,
                destination: protectedProject
            )
            let protectedPrefix = workDirectory.appending(path: "protected-layer")
            try toolchain.run(
                "nona",
                arguments: protectedIndices.flatMap { ["-i", "\($0)"] } + [
                    "-r", "ldr", "-m", "TIFF_m",
                    "-o", protectedPrefix.path(percentEncoded: false),
                    protectedProject.path(percentEncoded: false)
                ],
                in: workDirectory
            )

            var projectedProtection: [Int: Data] = [:]
            for index in protectedIndices {
                let projectedLayer = workDirectory.appending(
                    path: String(format: "protected-layer%04d.tif", index)
                )
                guard FileManager.default.fileExists(atPath: projectedLayer.path)
                else { continue }
                let normalized = workDirectory.appending(
                    path: "protected-normalized-\(index).tif"
                )
                try ProjectedLayerMaskService.normalize(
                    projectedLayer,
                    to: normalized
                )
                projectedProtection[index] = try ProjectedLayerMaskService
                    .alphaMask(from: normalized)
            }

            blendLayers = try layers.enumerated().map { index, layer in
                let masksFromOtherImages = projectedProtection.compactMap {
                    owner, mask in owner == index ? nil : mask
                }
                guard let exclusion = try ProjectedLayerMaskService.merged(
                    masksFromOtherImages
                ) else { return layer }
                let destination = workDirectory.appending(
                    path: "protected-blend-layer-\(index).tif"
                )
                try ProjectedLayerMaskService.normalize(
                    layer,
                    exclusionMask: exclusion,
                    to: destination
                )
                return destination
            }
        }
        let result = workDirectory.appending(path: "panorama.jpg")
        func blend(
            _ inputLayers: [URL],
            to output: URL
        ) throws {
            try toolchain.run(
                "enblend",
                arguments: [
                    "-f", "4000x2000+0+0", "--wrap=horizontal",
                    "--compression=92",
                    "--primary-seam-generator=\(Self.primarySeamGenerator)",
                    "--output=\(output.path(percentEncoded: false))"
                ]
                    + inputLayers.map { $0.path(percentEncoded: false) },
                in: workDirectory
            )
        }
        func blendCyclically(
            _ inputLayers: [URL],
            to output: URL
        ) throws {
            var blendError: Error?
            for offset in inputLayers.indices {
                try? FileManager.default.removeItem(at: output)
                do {
                    let orderedLayers = Array(inputLayers[offset...])
                        + Array(inputLayers[..<offset])
                    try blend(
                        orderedLayers,
                        to: output
                    )
                    return
                } catch {
                    blendError = error
                }
            }
            throw blendError ?? PanoramaEngineError.stitchingFailed(
                "Enblend kunde inte kombinera bildlagren."
            )
        }

        do {
            try blendCyclically(blendLayers, to: result)
        } catch {
            guard error.localizedDescription.contains(
                "degenerate image/mask geometry"
            ) else { throw error }
            // Valid projected masks can touch at a single pixel regardless of
            // lens type or image direction. Enblend rejects that topology
            // before calculating a seam. Moving only the alpha edge one pixel
            // inward removes the ambiguous contact while preserving the real
            // overlap between neighboring images.
            let insetLayers = try blendLayers.enumerated().map { index, layer in
                let destination = workDirectory.appending(
                    path: "inset-blend-layer-\(index).tif"
                )
                try ProjectedLayerMaskService.normalize(
                    layer,
                    insetsAlphaByOnePixel: true,
                    to: destination
                )
                return destination
            }
            try blendCyclically(insetLayers, to: result)
        }

        var nadirRepair: NadirRepairRegistrationResult?
        let repairHorizontalFieldOfView = try HuginProjectFile
            .horizontalFieldOfView(in: ringGeometryProject)
        if let repairImage = nadirRepairImages.first {
            log("Local nadir repair registration", images: [repairImage])
            let overlay = workDirectory.appending(path: "nadir-overlay.png")
            do {
                nadirRepair = try controlPoints.flatMap {
                    try sphericalRepairRegistration(
                        pole: .nadir, repairImage: repairImage,
                        panoramaImages: panorama.images,
                        ringImages: geometryRingImages,
                        ringProject: ringGeometryProject,
                        mask: masks[repairImage.id], controlPoints: $0,
                        outputURL: overlay, workDirectory: workDirectory,
                        toolchain: toolchain
                    )
                } ?? OpenCVNadirRepairRegistrar.register(
                    panoramaURL: result, repairImage: repairImage,
                    exclusionMaskData: masks[repairImage.id],
                    horizontalFieldOfView: repairHorizontalFieldOfView,
                    outputURL: overlay
                )
            } catch {
                log(
                    "Nadir repair skipped (\(error.localizedDescription))",
                    images: [repairImage]
                )
            }
        }
        var zenithRepair: NadirRepairRegistrationResult?
        if let repairImage = zenithRepairImages.first {
            log("Local zenith repair registration", images: [repairImage])
            let overlay = workDirectory.appending(path: "zenith-overlay.png")
            do {
                zenithRepair = try controlPoints.flatMap {
                    try sphericalRepairRegistration(
                        pole: .zenith, repairImage: repairImage,
                        panoramaImages: panorama.images,
                        ringImages: geometryRingImages,
                        ringProject: ringGeometryProject,
                        mask: masks[repairImage.id], controlPoints: $0,
                        outputURL: overlay, workDirectory: workDirectory,
                        toolchain: toolchain
                    )
                } ?? OpenCVNadirRepairRegistrar.register(
                    panoramaURL: result, repairImage: repairImage,
                    exclusionMaskData: masks[repairImage.id],
                    horizontalFieldOfView: repairHorizontalFieldOfView,
                    pole: .zenith, outputURL: overlay
                )
            } catch {
                log(
                    "Zenith repair skipped (\(error.localizedDescription))",
                    images: [repairImage]
                )
            }
        }

        let resultDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/Results/\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: resultDirectory,
            withIntermediateDirectories: true
        )
        let persistedResult = resultDirectory.appending(path: "panorama.jpg")
        try FileManager.default.copyItem(at: result, to: persistedResult)

        func persistedRepair(
            _ repair: NadirRepairRegistrationResult?,
            filename: String
        ) throws -> NadirRepairRegistrationResult? {
            guard let repair else { return nil }
            let destination = resultDirectory.appending(path: filename)
            try FileManager.default.copyItem(
                at: repair.overlayURL,
                to: destination
            )
            return NadirRepairRegistrationResult(
                overlayURL: destination,
                placement: repair.placement
            )
        }

        let optimizedImageLines = try HuginProjectFile.imageLines(
            in: finalGeometryProject
        )
        let rigImageLines = Dictionary(uniqueKeysWithValues:
            zip(ringImages, optimizedImageLines).map { image, line in
                (image.id, line)
            }
        )
        return PanoramaStitchResult(
            url: persistedResult,
            rigImageLines: rigImageLines,
            nadirRepair: try persistedRepair(
                nadirRepair,
                filename: "nadir-overlay.png"
            ),
            zenithRepair: try persistedRepair(
                zenithRepair,
                filename: "zenith-overlay.png"
            ),
            controlPointDiagnostics: controlPointDiagnostics
        )
    }

    private static func duplicateRepairMessage(
        direction: SourceImage.Direction,
        repairs: [SourceImage],
        allImages: [SourceImage]
    ) -> String {
        let numbers = repairs.compactMap { repair in
            allImages.firstIndex(where: { $0.id == repair.id }).map { $0 + 1 }
        }.map(String.init).joined(separator: ", ")
        return "Flera bilder är märkta \(direction.displayName) · Reparation "
            + "(bild \(numbers)). Välj rätt reparationsområde för varje bild."
    }

    private static func sphericalRepairRegistration(
        pole: PanoramaPole,
        repairImage: SourceImage,
        panoramaImages: [SourceImage],
        ringImages: [SourceImage],
        ringProject: URL,
        mask: Data?,
        controlPoints: [DiagnosticControlPoint],
        outputURL: URL,
        workDirectory: URL,
        toolchain: HuginToolchain
    ) throws -> NadirRepairRegistrationResult? {
        guard let repairIndex = panoramaImages.firstIndex(where: {
            $0.id == repairImage.id
        }) else { return nil }
        let ringIndexByID = Dictionary(uniqueKeysWithValues:
            ringImages.enumerated().map { ($0.element.id, $0.offset) }
        )
        let remapped: [PanoramaControlPoint] = controlPoints.compactMap { point in
            let other: Int
            let repairPoint: CGPoint
            let ringPoint: CGPoint
            if point.firstImage == repairIndex {
                other = point.secondImage
                repairPoint = CGPoint(x: point.firstX, y: point.firstY)
                ringPoint = CGPoint(x: point.secondX, y: point.secondY)
            } else if point.secondImage == repairIndex {
                other = point.firstImage
                repairPoint = CGPoint(x: point.secondX, y: point.secondY)
                ringPoint = CGPoint(x: point.firstX, y: point.firstY)
            } else { return nil }
            guard panoramaImages.indices.contains(other),
                  let ring = ringIndexByID[panoramaImages[other].id]
            else { return nil }
            return PanoramaControlPoint(
                firstImage: ring,
                secondImage: ringImages.count,
                firstX: ringPoint.x,
                firstY: ringPoint.y,
                secondX: repairPoint.x,
                secondY: repairPoint.y
            )
        }
        guard remapped.count >= 4 else { return nil }
        let prepared = workDirectory.appending(
            path: "hugin-\(pole.rawValue)-source.png"
        )
        try MaskedSourceImageWriter.write(
            sourceURL: repairImage.url,
            maskData: mask,
            clipsToFisheyeCircle: true,
            destinationURL: prepared
        )
        guard let preparedSource = CGImageSourceCreateWithURL(
            prepared as CFURL,
            nil
        ), let properties = CGImageSourceCopyPropertiesAtIndex(
            preparedSource,
            0,
            nil
        ) as? [CFString: Any],
            let preparedWidth = properties[kCGImagePropertyPixelWidth] as? Int,
            let preparedHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw PanoramaEngineError.stitchingFailed(
                "Den förberedda \(pole.rawValue)-bildens mått kunde inte läsas."
            )
        }
        let seeded = workDirectory.appending(
            path: "hugin-\(pole.rawValue)-seed.pto"
        )
        let optimized = workDirectory.appending(
            path: "hugin-\(pole.rawValue)-optimized.pto"
        )
        try HuginProjectFile.addingZenith(
            image: repairImage,
            renderedImageURL: prepared,
            pixelWidth: preparedWidth,
            pixelHeight: preparedHeight,
            orientation: PanoramaOrientation(
                yaw: 0,
                pitch: pole.pitchDegrees,
                roll: 0
            ),
            controlPoints: remapped,
            ringProject: ringProject,
            destination: seeded
        )
        try toolchain.run(
            "autooptimiser",
            arguments: ["-n", "-o", optimized.path(), seeded.path()],
            in: workDirectory
        )
        let sources = workDirectory.appending(
            path: "hugin-\(pole.rawValue)-sources.pto"
        )
        try HuginProjectFile.replacingImagePaths(
            in: optimized,
            with: ringImages.map(\.url) + [prepared],
            destination: sources
        )
        let render = workDirectory.appending(
            path: "hugin-\(pole.rawValue)-render.pto"
        )
        try toolchain.run(
            "pano_modify",
            arguments: [
                "-o", render.path(), "-p", "2", "--fov=360x180",
                "--canvas=4000x2000", sources.path()
            ],
            in: workDirectory
        )
        let prefix = workDirectory.appending(path: "hugin-\(pole.rawValue)-layer")
        try toolchain.run(
            "nona",
            arguments: [
                "-r", "ldr", "-m", "TIFF_m", "-i", "\(ringImages.count)",
                "-o", prefix.path(), render.path()
            ],
            in: workDirectory
        )
        guard let layer = try FileManager.default.contentsOfDirectory(
            at: workDirectory,
            includingPropertiesForKeys: nil
        ).first(where: {
            $0.lastPathComponent.hasPrefix(prefix.lastPathComponent)
                && ["tif", "tiff"].contains($0.pathExtension.lowercased())
        }) else { return nil }
        try OpenCVNadirRepairRegistrar.extractPoleOverlay(
            from: layer,
            pole: pole,
            outputURL: outputURL
        )
        let ringPanoramaPoints = try toolchain.panoramaCoordinates(
            in: render,
            points: remapped.map {
                ($0.firstImage, CGPoint(x: $0.firstX, y: $0.firstY))
            }
        )
        let repairPanoramaPoints = try toolchain.panoramaCoordinates(
            in: render,
            points: remapped.map {
                ($0.secondImage, CGPoint(x: $0.secondX, y: $0.secondY))
            }
        )
        let localPoints = zip(ringPanoramaPoints, repairPanoramaPoints)
            .compactMap { ringPanoramaPoint, repairPanoramaPoint
                -> DiagnosticControlPoint? in
                guard let ringLocal = OpenCVNadirRepairRegistrar
                    .localPoleCoordinate(
                        panoramaPoint: ringPanoramaPoint,
                        panoramaSize: CGSize(width: 4_000, height: 2_000),
                        pole: pole
                    ),
                    let repairLocal = OpenCVNadirRepairRegistrar
                    .localPoleCoordinate(
                        panoramaPoint: repairPanoramaPoint,
                        panoramaSize: CGSize(width: 4_000, height: 2_000),
                        pole: pole
                    ),
                    (0...1_600).contains(ringLocal.x),
                    (0...1_600).contains(ringLocal.y),
                    (0...1_600).contains(repairLocal.x),
                    (0...1_600).contains(repairLocal.y)
                else { return nil }
                return DiagnosticControlPoint(
                    firstImage: 0,
                    secondImage: 1,
                    firstX: repairLocal.x,
                    firstY: repairLocal.y,
                    secondX: ringLocal.x,
                    secondY: ringLocal.y
                )
            }
        var placement = NadirRepairPlacement(
            imageID: repairImage.id,
            localHomography: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            matchedFeatureCount: remapped.count,
            localViewFieldOfView: 120,
            controlPoints: localPoints,
            sphericalProjection: true
        )
        // Hugin establishes the spherical direction. A similarity transform
        // then supplies only the missing coarse translation, rotation and
        // uniform scale caused by the hand-held camera position. Perspective,
        // shear and corner stretch remain exclusively manual fine tuning.
        if localPoints.count >= 6 {
            let coarse = try OpenCVNadirRepairRegistrar
                .coarseSimilarityPlacement(bySolving: localPoints, from: placement)
            placement = coarse.0
            let coarseURL = outputURL.deletingLastPathComponent().appending(
                path: "\(pole.rawValue)-coarse-overlay.png"
            )
            try OpenCVNadirRepairRegistrar.warpPoleOverlay(
                at: outputURL,
                using: placement,
                outputURL: coarseURL
            )
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: coarseURL, to: outputURL)
        }
        let storedPoints = placement.controlPoints ?? remapped.map {
            DiagnosticControlPoint(
                firstImage: $0.firstImage,
                secondImage: $0.secondImage,
                firstX: $0.firstX,
                firstY: $0.firstY,
                secondX: $0.secondX,
                secondY: $0.secondY
            )
        }
        placement.controlPoints = storedPoints
        return NadirRepairRegistrationResult(
            overlayURL: outputURL,
            placement: placement
        )
    }

    static func robustControlPoints(
        _ points: [DiagnosticControlPoint],
        errors: [Double]
    ) -> [DiagnosticControlPoint] {
        guard points.count == errors.count, points.count >= 10 else {
            return points
        }
        let sortedErrors = errors.sorted()
        let median = sortedErrors[sortedErrors.count / 2]
        let deviations = errors.map { abs($0 - median) }.sorted()
        let medianAbsoluteDeviation = deviations[deviations.count / 2]
        // Dense automatic graphs from a monopod often contain a coherent
        // low-error rotation plus a moderate residual tail from nearby
        // objects. An 8 px / 6-MAD floor lets that parallax bend the shared
        // lens and poses. Keep the robust core tighter; sparse cycles bypass
        // this pass, and the best points of every pair are retained below so
        // a real narrow bridge is not disconnected.
        let threshold = max(5, median + 3 * medianAbsoluteDeviation)
        let pairRetentionThreshold = min(80, max(24, threshold * 2))

        let indicesByPair = Dictionary(grouping: points.indices) {
            points[$0].pair
        }
        var acceptedIndices = Set<Int>()
        for indices in indicesByPair.values {
            // Four points keep a pair constrained even when an entire small
            // group is somewhat noisier than the global distribution. Never
            // preserve them unconditionally, though: a false extra pair can
            // otherwise survive with four thousand-pixel residuals and pull
            // the complete Sigma solution away from its valid ring.
            let bestIndices = indices.sorted { errors[$0] < errors[$1] }
            acceptedIndices.formUnion(bestIndices.prefix(4).filter {
                errors[$0].isFinite
                    && errors[$0] <= pairRetentionThreshold
            })
            acceptedIndices.formUnion(indices.filter {
                errors[$0].isFinite && errors[$0] <= threshold
            })
        }
        return points.indices.compactMap {
            acceptedIndices.contains($0) ? points[$0] : nil
        }
    }

    /// The same predictable, geometry-based seam generator is used for every
    /// panorama, independently of lens, masks, image direction and image count.
    static let primarySeamGenerator = "nearest-feature-transform"

    static func treatsSuppliedControlPointsAsEdited(
        hasSuppliedControlPoints: Bool,
        controlPointsAreAuthoritative: Bool,
        automaticStabilizationAttempt: Int
    ) -> Bool {
        // A recovery pass receives the app's own generated points so it can
        // restart from exactly that connected graph. Those points are not a
        // manual edit: robust residual filtering must remain available or a
        // sparse ring can repeat the same marginally unstable solve forever.
        hasSuppliedControlPoints
            && controlPointsAreAuthoritative
            && automaticStabilizationAttempt == 0
    }

    static func needsAutomaticStabilization(errors: [Double]) -> Bool {
        let finiteErrors = errors.filter(\.isFinite).sorted()
        guard finiteErrors.count >= 10 else { return false }
        let median = finiteErrors[finiteErrors.count / 2]
        let p90 = finiteErrors[min(
            finiteErrors.count - 1,
            Int(Double(finiteErrors.count) * 0.9)
        )]
        return median > 4 || p90 > 8
    }

    static func controlPointComponents(
        imageCount: Int,
        controlPoints: [DiagnosticControlPoint]
    ) -> [[Int]] {
        guard imageCount > 0 else { return [] }
        var neighbors = Array(repeating: Set<Int>(), count: imageCount)
        for point in controlPoints
        where (0..<imageCount).contains(point.firstImage)
            && (0..<imageCount).contains(point.secondImage) {
            neighbors[point.firstImage].insert(point.secondImage)
            neighbors[point.secondImage].insert(point.firstImage)
        }
        var remaining = Set(0..<imageCount)
        var components: [[Int]] = []
        while let start = remaining.first {
            var component: [Int] = []
            var pending = [start]
            remaining.remove(start)
            while let current = pending.popLast() {
                component.append(current)
                for neighbor in neighbors[current] where remaining.remove(neighbor) != nil {
                    pending.append(neighbor)
                }
            }
            components.append(component.sorted())
        }
        return components.sorted { ($0.first ?? 0) < ($1.first ?? 0) }
    }

    static func hasReliable360DegreeBackbone(
        orientations: [PanoramaOrientation],
        horizontalFieldOfView: Double,
        controlPoints: [DiagnosticControlPoint],
        logsDiagnostics: Bool = false
    ) -> Bool {
        let reliablePairs = reliableControlPointPairs(
            imageCount: orientations.count,
            controlPoints: controlPoints
        )
        let cycleComponents = reliableCycleComponents(
            imageCount: orientations.count,
            reliablePairs: reliablePairs
        )
        // Consecutive cameras that truly overlap must be closer than roughly
        // one input field of view. The tolerance absorbs lens-model and CP
        // noise without allowing a local overlap triangle to masquerade as a
        // complete 360-degree backbone.
        let maximumAllowedYawGap = min(
            180,
            max(45, horizontalFieldOfView * 1.15)
        )
        let closes = cycleComponents.contains { component in
            let yaws = component.compactMap { index -> Double? in
                guard orientations.indices.contains(index),
                      orientations[index].yaw.isFinite else { return nil }
                var yaw = orientations[index].yaw
                    .truncatingRemainder(dividingBy: 360)
                if yaw < 0 { yaw += 360 }
                return yaw
            }.sorted()
            guard yaws.count >= 3 else { return false }
            var maximumGap = yaws[0] + 360 - yaws[yaws.count - 1]
            for index in 1..<yaws.count {
                maximumGap = max(maximumGap, yaws[index] - yaws[index - 1])
            }
            return maximumGap <= maximumAllowedYawGap
        }
        if logsDiagnostics, !closes {
            print(
                "[PanoWizard] Reliable cycle components: "
                    + cycleComponents.map { component in
                        component.map(String.init).joined(separator: ",")
                    }.joined(separator: " | ")
            )
        }
        return closes
    }

    static func weakFourImageRingImages(
        controlPoints: [DiagnosticControlPoint]
    ) -> [Int] {
        imagesOutsideReliableRingClosure(
            imageCount: 4,
            requiredImageIndices: Array(0..<4),
            controlPoints: controlPoints
        )
    }

    static func imagesOutsideReliableRingClosure(
        imageCount: Int,
        requiredImageIndices: [Int],
        controlPoints: [DiagnosticControlPoint],
        logsDiagnostics: Bool = false
    ) -> [Int] {
        let pointsByPair = Dictionary(grouping: controlPoints, by: \.pair)
        let reliablePairs = reliableControlPointPairs(
            imageCount: imageCount,
            controlPoints: controlPoints
        )
        let imagesInCycles = Set(
            reliableCycleComponents(
                imageCount: imageCount,
                reliablePairs: reliablePairs
            ).flatMap { $0 }
        )
        let outside = requiredImageIndices.sorted().filter {
            (0..<imageCount).contains($0) && !imagesInCycles.contains($0)
        }
        if logsDiagnostics, !outside.isEmpty {
            print(
                "[PanoWizard] Reliable ring pairs: "
                    + reliablePairs.map {
                        "\($0.firstImage)-\($0.secondImage)"
                    }.joined(separator: ", ")
            )
            for (pair, points) in pointsByPair.sorted(by: { $0.key < $1.key }) {
                let errors = points.compactMap(\.error).filter(\.isFinite).sorted()
                guard !errors.isEmpty else { continue }
                print(
                    "[PanoWizard] Ring pair residual "
                        + "\(pair.firstImage)-\(pair.secondImage): "
                        + "count=\(errors.count) "
                        + String(
                            format: "median=%.3f p90=%.3f",
                            errors[errors.count / 2],
                            errors[min(
                                errors.count - 1,
                                Int(Double(errors.count) * 0.9)
                            )]
                        )
                )
            }
        }
        return outside
    }

    static func reliableControlPointPairs(
        imageCount: Int,
        controlPoints: [DiagnosticControlPoint]
    ) -> [ControlPointPair.ID] {
        Dictionary(grouping: controlPoints, by: \.pair).compactMap {
            pair, points in
            guard (0..<imageCount).contains(pair.firstImage),
                  (0..<imageCount).contains(pair.secondImage) else {
                return nil as ControlPointPair.ID?
            }
            let errors = points.compactMap(\.error)
            let hasReliableResiduals: Bool
            if points.count >= 4, errors.count == points.count {
                let sortedErrors = errors.filter(\.isFinite).sorted()
                if sortedErrors.count == errors.count {
                    let median = sortedErrors[sortedErrors.count / 2]
                    let p90 = sortedErrors[min(
                        sortedErrors.count - 1,
                        Int(Double(sortedErrors.count) * 0.9)
                    )]
                    // A real transition can contain a few parallax-heavy
                    // points, especially where nadir exposures overlap the
                    // tripod ring. Judge the pair by its robust distribution
                    // instead of one worst point, while still rejecting a
                    // consistently bad bridge that could fold the panorama.
                    hasReliableResiduals = median <= 5 && p90 <= 8
                } else {
                    hasReliableResiduals = false
                }
            } else {
                hasReliableResiduals = false
            }
            let isReliable = errors.isEmpty
                ? points.count >= 8
                : errors.count == points.count && hasReliableResiduals
            return isReliable ? pair : nil
        }.sorted()
    }

    static func reliableCycleComponents(
        imageCount: Int,
        reliablePairs: [ControlPointPair.ID]
    ) -> [[Int]] {
        var adjacency = Array(
            repeating: [(neighbor: Int, edge: Int)](),
            count: imageCount
        )
        for (edge, pair) in reliablePairs.enumerated() {
            adjacency[pair.firstImage].append((pair.secondImage, edge))
            adjacency[pair.secondImage].append((pair.firstImage, edge))
        }

        var discovery = Array(repeating: -1, count: imageCount)
        var low = Array(repeating: -1, count: imageCount)
        var nextDiscovery = 0
        var bridges = Set<Int>()
        func visit(_ image: Int, parentEdge: Int?) {
            discovery[image] = nextDiscovery
            low[image] = nextDiscovery
            nextDiscovery += 1
            for connection in adjacency[image] {
                if connection.edge == parentEdge { continue }
                if discovery[connection.neighbor] < 0 {
                    visit(connection.neighbor, parentEdge: connection.edge)
                    low[image] = min(low[image], low[connection.neighbor])
                    if low[connection.neighbor] > discovery[image] {
                        bridges.insert(connection.edge)
                    }
                } else {
                    low[image] = min(
                        low[image],
                        discovery[connection.neighbor]
                    )
                }
            }
        }
        for image in 0..<imageCount where discovery[image] < 0 {
            visit(image, parentEdge: nil)
        }

        var remaining = Set(0..<imageCount)
        var components: [[Int]] = []
        while let start = remaining.first {
            var component: [Int] = []
            var pending = [start]
            remaining.remove(start)
            while let image = pending.popLast() {
                component.append(image)
                for connection in adjacency[image]
                    where !bridges.contains(connection.edge) {
                    if remaining.remove(connection.neighbor) != nil {
                        pending.append(connection.neighbor)
                    }
                }
            }
            if component.count >= 3 {
                components.append(component.sorted())
            }
        }
        return components.sorted { ($0.first ?? 0) < ($1.first ?? 0) }
    }

    static func preservesSuppliedRingGraph(
        hasSuppliedControlPoints: Bool,
        isCircularFisheye: Bool
    ) -> Bool {
        hasSuppliedControlPoints || isCircularFisheye
    }

    static func needsUprightCanonicalization(
        orientations: [PanoramaOrientation]
    ) -> Bool {
        let nonPolar = orientations.filter { abs($0.pitch) < 60 }
        guard nonPolar.count >= 2 else { return false }
        let invertedCount = nonPolar.count {
            var signedRoll = $0.roll.truncatingRemainder(dividingBy: 360)
            if signedRoll <= -180 { signedRoll += 360 }
            if signedRoll > 180 { signedRoll -= 360 }
            return abs(signedRoll) > 90
        }
        return invertedCount * 2 > nonPolar.count
    }

    static func projectImageNumbers(
        for ringIndices: [Int],
        ringImages: [SourceImage],
        panoramaImages: [SourceImage]
    ) -> [Int] {
        let panoramaIndexByID = Dictionary(uniqueKeysWithValues:
            panoramaImages.enumerated().map { ($0.element.id, $0.offset) }
        )
        return ringIndices.compactMap { ringIndex in
            guard ringImages.indices.contains(ringIndex),
                  let panoramaIndex = panoramaIndexByID[ringImages[ringIndex].id]
            else { return nil }
            return panoramaIndex + 1
        }
    }

    static func remappingFisheyePoint(
        x: Double,
        y: Double,
        width: Int,
        height: Int,
        sourceFactor: Double,
        destinationFactor: Double
    ) -> (Double, Double) {
        let centerX = (Double(width) - 1) / 2
        let centerY = (Double(height) - 1) / 2
        let dx = x - centerX
        let dy = y - centerY
        let sourceRadius = hypot(dx, dy)
        let circleRadius = Double(max(width, height)) * 0.4787
        guard sourceRadius > 0, sourceRadius <= circleRadius,
              sourceFactor < 0, destinationFactor < 0 else {
            return (x, y)
        }
        let normalizedSourceRadius = sourceRadius / circleRadius
        let sourceEdge = sin(sourceFactor * .pi / 2)
        let destinationEdge = sin(destinationFactor * .pi / 2)
        let theta = asin(
            min(1, max(-1, normalizedSourceRadius * sourceEdge))
        ) / sourceFactor
        let normalizedDestinationRadius = sin(destinationFactor * theta)
            / destinationEdge
        let scale = normalizedDestinationRadius * circleRadius / sourceRadius
        return (centerX + dx * scale, centerY + dy * scale)
    }

    private static func replacingURL(
        of image: SourceImage,
        with url: URL
    ) -> SourceImage {
        SourceImage(
            id: image.id,
            url: url,
            captureDate: image.captureDate,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight,
            cameraModel: image.cameraModel,
            lens: image.lens,
            direction: image.direction,
            role: image.role
        )
    }

    private static func initialFieldOfView(
        _ configuration: StitchingConfiguration,
        images: [SourceImage]
    ) -> Double {
        switch configuration.lensProfile {
        case .sigma8DX:
            return 113.4
        case .nikon105DX:
            return 87.44
        case .automatic:
            if images.contains(where: {
                $0.lens.kind == .fisheye
                    && ($0.lens.focalLengthIn35mm.map {
                        (11...13).contains($0)
                    } ?? false)
            }) {
                return 120
            }
            return configuration.inputHorizontalFieldOfView
        case .custom:
            return configuration.inputHorizontalFieldOfView
        }
    }

    private static func log(_ stage: String, images: [SourceImage]) {
        let names = images.map(\.filename).joined(separator: ", ")
        print("[PanoWizard] \(stage): \(names)")
    }
}
