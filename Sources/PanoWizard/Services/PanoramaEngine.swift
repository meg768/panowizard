import Foundation

protocol PanoramaEngine: Sendable {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        controlPointMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint]?,
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult

    func optimizeControlPoints(
        _ panorama: PanoramaSet,
        controlPointMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint],
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
        controlPointMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint]?,
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.stitchSynchronously(
                panorama,
                masks: masks,
                controlPointMasks: controlPointMasks,
                controlPoints: controlPoints,
                configuration: configuration,
                rendersPanorama: true
            )
        }.value
    }

    func optimizeControlPoints(
        _ panorama: PanoramaSet,
        controlPointMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint],
        configuration: StitchingConfiguration
    ) async throws -> ControlPointOptimizationResult {
        try await Task.detached(priority: .userInitiated) {
            let result = try Self.stitchSynchronously(
                panorama,
                masks: [:],
                controlPointMasks: controlPointMasks,
                controlPoints: controlPoints,
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
        controlPointMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint]?,
        configuration: StitchingConfiguration,
        rendersPanorama: Bool
    ) throws -> PanoramaStitchResult {
        let alignmentImages = panorama.images.filter { $0.role == .alignment }
        let fillOnlyImages = panorama.images.filter { $0.role == .fillOnly }
        let ringImages = alignmentImages.filter { $0.direction == .horizontal }
        // A hand-held zenith marked as Reparation still uses the frozen-ring
        // zenith registrar. Only its own pose is optimized; the ring is
        // checked below and rejected if any ring orientation changes.
        let zenithImages = alignmentImages.filter { $0.direction == .zenith }
        let unsupported = alignmentImages.filter { $0.direction == .nadir }
        let nadirRepairImages = fillOnlyImages.filter { $0.direction == .nadir }
        let zenithRepairImages = fillOnlyImages.filter { $0.direction == .zenith }
        let unsupportedRepairImages = fillOnlyImages.filter {
            $0.direction == .horizontal
        }

        guard ringImages.count >= 2 else {
            throw PanoramaEngineError.insufficientImages
        }
        guard zenithImages.count <= 1 else {
            throw PanoramaEngineError.stitchingFailed(
                "Den här första stitchmotorn stöder en zenitbild."
            )
        }
        guard unsupported.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "En nadirbild måste ha bildrollen Reparation."
            )
        }
        guard unsupportedRepairImages.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "En horisontell bild kan inte användas som polreparation."
            )
        }
        guard nadirRepairImages.count <= 1 else {
            throw PanoramaEngineError.stitchingFailed(
                "I den här etappen stöds en nadirreparation."
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

        let geometryDirectory = workDirectory.appending(
            path: "geometry-sources",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: geometryDirectory,
            withIntermediateDirectories: true
        )
        let geometryInputs = ringImages + zenithImages
        let geometryImages = try geometryInputs.enumerated().map { index, image in
            let destination = geometryDirectory.appending(
                path: "source-\(index).tif"
            )
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: controlPointMasks[image.id],
                clipsToFisheyeCircle: false,
                destinationURL: destination
            )
            return Self.replacingURL(of: image, with: destination)
        }
        let geometryByID = Dictionary(
            uniqueKeysWithValues: geometryImages.map { ($0.id, $0) }
        )
        let geometryRingImages = ringImages.map { geometryByID[$0.id] ?? $0 }
        let geometryZenithImages = zenithImages.map { geometryByID[$0.id] ?? $0 }

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
        let normalizedMatchingProject = workDirectory.appending(
            path: "03-normalized-matching.pto"
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
        let usesEditedControlPoints = controlPoints != nil
        let ringControlPoints = try controlPoints?.map {
            PanoramaControlPoint(
                firstImage: $0.firstImage,
                secondImage: $0.secondImage,
                firstX: $0.firstX,
                firstY: $0.firstY,
                secondX: $0.secondX,
                secondY: $0.secondY
            )
        } ?? OpenCVControlPointMatcher.ring(
            images: geometryRingImages,
            horizontalFieldOfView: matchingFieldOfView
        )
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
            if isCircularFisheye, controlPoints == nil {
                // The first OpenCV pass only discovers duplicate exposures
                // and the coarse ring. Find the production control points on
                // that prealigned ring with Hugin itself, so feature
                // normalization and bundle adjustment use the exact same
                // calibrated fisheye projection.
                try HuginProjectFile.configuringSigmaPoseOptimization(
                    from: seededProject,
                    to: normalizedMatchingProject,
                    nominalYaws: nominalYaws,
                    horizontalFieldOfView: horizontalFieldOfView
                )
                try toolchain.run(
                    "cpfind",
                    arguments: [
                        "--prealigned",
                        "--ransacmode=rpy",
                        "--ransacdist=12",
                        "--minmatches=6",
                        "--sieve2size=2",
                        "--ncores=1",
                        "-o", controlPointProject.path(percentEncoded: false),
                        normalizedMatchingProject.path(percentEncoded: false)
                    ],
                    in: workDirectory
                )
            }
            if usesEditedControlPoints {
                // A manual/imported CP set is the experiment's input. Do not
                // silently discard pairs or reduce it to PanoWizard's
                // automatically selected ring backbone.
                try FileManager.default.copyItem(
                    at: controlPointProject,
                    to: ringBackboneProject
                )
            } else {
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
        if usesEditedControlPoints {
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
           acceptedPoints.count < initiallyOptimizedPoints.count {
            let filteredProject = workDirectory.appending(
                path: "05-ring-outliers-removed.pto"
            )
            try HuginProjectFile.filteringControlPoints(
                from: optimizedRingProject,
                to: filteredProject
            ) { point in
                acceptedPoints.contains { accepted in
                    accepted.firstImage == point.firstImage
                        && accepted.secondImage == point.secondImage
                        && accepted.firstX == point.firstX
                        && accepted.firstY == point.firstY
                        && accepted.secondX == point.secondX
                        && accepted.secondY == point.secondY
                }
            }
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
            finalOptimizedRingProject = robustRingProject
        }
        var cleanedDiagnosticPoints = try HuginProjectFile.controlPoints(
            in: finalOptimizedRingProject
        )
        let pointErrors = try toolchain.controlPointErrors(
            in: finalOptimizedRingProject,
            points: cleanedDiagnosticPoints
        )
        for index in cleanedDiagnosticPoints.indices {
            cleanedDiagnosticPoints[index].error = pointErrors[index]
        }
        let controlPointDiagnostics = ControlPointDiagnostics(
            images: ringImages,
            rawPoints: try HuginProjectFile.controlPoints(
                in: controlPointProject
            ),
            cleanedPoints: cleanedDiagnosticPoints
        )
        if !rendersPanorama {
            return PanoramaStitchResult(
                url: nil,
                rigImageLines: [:],
                nadirRepair: nil,
                zenithRepair: nil,
                controlPointDiagnostics: controlPointDiagnostics
            )
        }

        let ringGeometryProject = finalOptimizedRingProject
        var finalGeometryProject = ringGeometryProject
        var orderedImages = ringImages
        if let zenith = geometryZenithImages.first {
            log("Frozen-ring zenith registration", images: [zenith])
            let ringOrientations = try HuginProjectFile.orientations(
                in: ringGeometryProject
            )
            let optimizedFieldOfView = try HuginProjectFile
                .horizontalFieldOfView(in: ringGeometryProject)
            let placement = try OpenCVControlPointMatcher.zenith(
                ringImages: geometryRingImages,
                ringOrientations: ringOrientations,
                zenithImage: zenith,
                horizontalFieldOfView: optimizedFieldOfView
            )
            let zenithProject = workDirectory.appending(path: "06-zenith.pto")
            let cleanedZenithProject = workDirectory.appending(
                path: "07-zenith-cleaned.pto"
            )
            let optimizedZenithProject = workDirectory.appending(
                path: "08-geometry.pto"
            )
            try HuginProjectFile.addingZenith(
                image: zenith,
                orientation: placement.orientation,
                controlPoints: placement.controlPoints,
                ringProject: ringGeometryProject,
                destination: zenithProject
            )
            try toolchain.run(
                "cpclean",
                arguments: [
                    "-o", cleanedZenithProject.path(percentEncoded: false),
                    zenithProject.path(percentEncoded: false)
                ],
                in: workDirectory
            )
            try toolchain.run(
                "autooptimiser",
                arguments: [
                    "-n",
                    "-o", optimizedZenithProject.path(percentEncoded: false),
                    cleanedZenithProject.path(percentEncoded: false)
                ],
                in: workDirectory
            )
            let frozenRing = try HuginProjectFile.orientations(
                in: ringGeometryProject
            )
            let resultingRing = Array(
                try HuginProjectFile.orientations(in: optimizedZenithProject)
                    .prefix(ringImages.count)
            )
            guard frozenRing == resultingRing else {
                throw PanoramaEngineError.stitchingFailed(
                    "Zenitsteget försökte ändra den frysta ringgeometrin."
                )
            }
            finalGeometryProject = optimizedZenithProject
            orderedImages.append(zenith)
        }

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
        let renderOrientations = try HuginProjectFile.orientations(
            in: finalGeometryProject
        )
        let backgroundLayerIndices = Self.bestBackgroundLayerIndices(
            orientations: renderOrientations,
            controlPoints: cleanedDiagnosticPoints
        )
        print(
            "[PanoWizard] Enblend representatives: "
                + backgroundLayerIndices.sorted()
                    .map { String($0 + 1) }
                    .joined(separator: ", ")
        )
        let preparedImages = try orderedImages.enumerated().map { index, image in
            let destination = preparedDirectory.appending(
                path: "source-\(index).tif"
            )
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: masks[image.id],
                clipsToFisheyeCircle: clipsToCircle,
                destinationURL: destination
            )
            return destination
        }
        let renderSourcesProject = workDirectory.appending(
            path: "09-render-sources.pto"
        )
        let seamCenteredProject = workDirectory.appending(
            path: "09-seam-centered.pto"
        )
        try HuginProjectFile.centeringPanoramaSeamBetweenRingImages(
            from: finalGeometryProject,
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
        let backgroundLayers = layers.enumerated().compactMap { index, layer in
            backgroundLayerIndices.contains(index) ? layer : nil
        }
        let result = workDirectory.appending(path: "panorama.jpg")
        let blendArguments = [
            "-f", "4000x2000+0+0",
            "--wrap=horizontal",
            "--compression=92",
            "--output=\(result.path(percentEncoded: false))"
        ] + backgroundLayers.map { $0.path(percentEncoded: false) }
        do {
            try toolchain.run(
                "enblend",
                arguments: blendArguments,
                in: workDirectory
            )
        } catch {
            try toolchain.run(
                "enblend",
                arguments: ["--no-optimize"] + blendArguments,
                in: workDirectory
            )
        }

        var nadirRepair: NadirRepairRegistrationResult?
        if let repairImage = nadirRepairImages.first {
            log("Local nadir repair registration", images: [repairImage])
            let overlay = workDirectory.appending(path: "nadir-overlay.png")
            nadirRepair = try OpenCVNadirRepairRegistrar.register(
                panoramaURL: result,
                repairImage: repairImage,
                exclusionMaskData: masks[repairImage.id],
                horizontalFieldOfView: horizontalFieldOfView,
                outputURL: overlay
            )
        }
        var zenithRepair: NadirRepairRegistrationResult?
        if let repairImage = zenithRepairImages.first {
            log("Local zenith repair registration", images: [repairImage])
            let overlay = workDirectory.appending(path: "zenith-overlay.png")
            zenithRepair = try OpenCVNadirRepairRegistrar.register(
                panoramaURL: result,
                repairImage: repairImage,
                exclusionMaskData: masks[repairImage.id],
                horizontalFieldOfView: horizontalFieldOfView,
                pole: .zenith,
                outputURL: overlay
            )
        }

        return PanoramaStitchResult(
            url: result,
            rigImageLines: [:],
            nadirRepair: nadirRepair,
            zenithRepair: zenithRepair,
            controlPointDiagnostics: controlPointDiagnostics
        )
    }

    private static func robustControlPoints(
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
        let threshold = max(8, median + 6 * medianAbsoluteDeviation)

        let indicesByPair = Dictionary(grouping: points.indices) {
            points[$0].pair
        }
        var acceptedIndices = Set<Int>()
        for indices in indicesByPair.values {
            // Four points keep a pair constrained even when an entire small
            // group is somewhat noisier than the global distribution.
            let bestIndices = indices.sorted { errors[$0] < errors[$1] }
            acceptedIndices.formUnion(bestIndices.prefix(4))
            acceptedIndices.formUnion(indices.filter {
                errors[$0].isFinite && errors[$0] <= threshold
            })
        }
        return points.indices.compactMap {
            acceptedIndices.contains($0) ? points[$0] : nil
        }
    }

    private static func bestBackgroundLayerIndices(
        orientations: [PanoramaOrientation],
        controlPoints: [DiagnosticControlPoint]
    ) -> Set<Int> {
        var groups: [[Int]] = []
        for index in orientations.indices {
            if let groupIndex = groups.firstIndex(where: { group in
                group.contains {
                    representsSameView(
                        orientations[$0],
                        orientations[index]
                    )
                }
            }) {
                groups[groupIndex].append(index)
            } else {
                groups.append([index])
            }
        }
        guard groups.contains(where: { $0.count > 1 }) else {
            return Set(orientations.indices)
        }

        let orderedGroups = groups.sorted {
            normalizedYaw(orientations[$0[0]].yaw)
                < normalizedYaw(orientations[$1[0]].yaw)
        }
        var bestSelection = orderedGroups.map { $0[0] }
        var bestScore = Double.infinity
        var selection: [Int] = []
        let verticalPositions = controlPoints.flatMap {
            [$0.firstY, $0.secondY]
        }.sorted()
        let groundBoundary = verticalPositions.isEmpty
            ? 0
            : verticalPositions[verticalPositions.count / 2]

        func evaluate(_ candidate: [Int]) -> Double {
            guard candidate.count > 1 else { return 0 }
            var score = 0.0
            for index in candidate.indices {
                let first = candidate[index]
                let second = candidate[(index + 1) % candidate.count]
                let matchingPoints = controlPoints.filter { point in
                    let matches = point.firstImage == first
                        && point.secondImage == second
                        || point.firstImage == second
                        && point.secondImage == first
                    return matches && point.error != nil
                }
                let errors = matchingPoints.compactMap(\.error)
                guard !errors.isEmpty else {
                    score += 1_000
                    continue
                }
                let mean = errors.reduce(0, +) / Double(errors.count)
                let maximum = errors.max() ?? mean
                let groundErrors = matchingPoints.compactMap {
                    ($0.firstY + $0.secondY) / 2 >= groundBoundary
                        ? $0.error
                        : nil
                }
                let groundMean = groundErrors.isEmpty
                    ? mean
                    : groundErrors.reduce(0, +) / Double(groundErrors.count)
                let groundMaximum = groundErrors.max() ?? maximum
                // The nadir-facing half contains the paving and exposes small
                // parallax errors much more clearly than sky or foliage.
                score += mean + maximum * 0.15
                score += groundMean * 2 + groundMaximum * 0.5
                score += 8 / Double(errors.count)
            }
            return score
        }

        func search(groupIndex: Int) {
            if groupIndex == orderedGroups.count {
                let score = evaluate(selection)
                if score < bestScore {
                    bestScore = score
                    bestSelection = selection
                }
                return
            }
            for imageIndex in orderedGroups[groupIndex] {
                selection.append(imageIndex)
                search(groupIndex: groupIndex + 1)
                selection.removeLast()
            }
        }

        search(groupIndex: 0)
        return Set(bestSelection)
    }

    private static func normalizedYaw(_ yaw: Double) -> Double {
        let normalized = yaw.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }

    private static func representsSameView(
        _ lhs: PanoramaOrientation,
        _ rhs: PanoramaOrientation
    ) -> Bool {
        func wrappedDifference(_ first: Double, _ second: Double) -> Double {
            let difference = abs(first - second).truncatingRemainder(
                dividingBy: 360
            )
            return min(difference, 360 - difference)
        }
        return wrappedDifference(lhs.yaw, rhs.yaw) < 8
            && abs(lhs.pitch - rhs.pitch) < 8
            && wrappedDifference(lhs.roll, rhs.roll) < 8
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
