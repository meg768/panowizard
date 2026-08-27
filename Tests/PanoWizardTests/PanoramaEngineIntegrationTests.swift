import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PanoWizard

struct PanoramaEngineIntegrationTests {
    @Test
    func stitchesImageFolderWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sourcePath = environment[
            "PANOWIZARD_FOLDER_PROJECT_SOURCE"
        ], let outputPath = environment[
            "PANOWIZARD_FOLDER_PROJECT_OUTPUT"
        ] else { return }

        let source = URL(fileURLWithPath: sourcePath)
        let sourceImages = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            let supportedExtensions = ["jpg", "jpeg", "png", "tif", "tiff"]
            return supportedExtensions.contains(url.pathExtension.lowercased())
        }
        let imported = await ImageImportService(
            metadataReader: ImageMetadataReader()
        ).load(from: sourceImages)
        var images = imported.images.sorted {
            $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        }
        #expect(!images.isEmpty)
        #expect(imported.skippedFiles == 0)

        let disabledNumbers = Set(
            (environment["PANOWIZARD_FOLDER_DISABLED_IMAGES"] ?? "")
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        )
        for index in images.indices where disabledNumbers.contains(index + 1) {
            images[index].isEnabled = false
        }
        if environment["PANOWIZARD_FOLDER_LAST_IS_NADIR"] == "1",
           let last = images.indices.last {
            images[last].role = .fillOnly
            images[last].direction = .nadir
        }
        if let zenithNumber = environment[
            "PANOWIZARD_FOLDER_ZENITH_IMAGE"
        ].flatMap(Int.init), images.indices.contains(zenithNumber - 1) {
            images[zenithNumber - 1].role = .fillOnly
            images[zenithNumber - 1].direction = .zenith
        }

        let lensProfile = environment[
            "PANOWIZARD_FOLDER_LENS_PROFILE"
        ].flatMap(StitchingConfiguration.LensProfile.init(rawValue:))
            ?? .sigma8DX
        let inputFieldOfView = lensProfile.defaultHorizontalFieldOfView
            ?? 165.38
        let configuration = StitchingConfiguration(
            engine: .automatic,
            projection: .automatic,
            lensProfile: lensProfile,
            inputHorizontalFieldOfView: inputFieldOfView
        )
        var project = PanoProject(
            title: source.lastPathComponent,
            images: images,
            stitching: configuration
        )
        let requestedPairs = (environment[
            "PANOWIZARD_FOLDER_MANUAL_PAIRS"
        ] ?? "").split(separator: ",").compactMap { value -> (Int, Int)? in
            let numbers = value.split(separator: "-").compactMap { Int($0) }
            guard numbers.count == 2 else { return nil }
            return (numbers[0] - 1, numbers[1] - 1)
        }
        let usesNominalRing = environment[
            "PANOWIZARD_FOLDER_NOMINAL_RING"
        ] == "1"
        let suppliedControlPoints: [DiagnosticControlPoint]?
        if environment["PANOWIZARD_FOLDER_WIZARD_POINTS"] == "1" {
            let ringIndices = images.indices.filter {
                images[$0].isEnabled && images[$0].role != .fillOnly
            }
            let ring = ringIndices.map { images[$0] }
            let points = try OpenCVControlPointMatcher.ring(
                images: ring,
                horizontalFieldOfView: inputFieldOfView,
                lensProfile: lensProfile
            )
            print("PANOWIZARD_FOLDER_WIZARD_POINTS=\(points.count)")
            suppliedControlPoints = points.map { point in
                DiagnosticControlPoint(
                    firstImage: ringIndices[point.firstImage],
                    secondImage: ringIndices[point.secondImage],
                    firstX: point.firstX,
                    firstY: point.firstY,
                    secondX: point.secondX,
                    secondY: point.secondY
                )
            }
        } else if let projectPath = environment[
            "PANOWIZARD_FOLDER_CONTROL_POINTS_PROJECT"
        ] {
            let data = try Data(contentsOf: URL(fileURLWithPath: projectPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            suppliedControlPoints = try decoder.decode(
                PanoProject.self,
                from: data
            ).controlPoints
        } else if usesNominalRing {
            let ringIndices = images.indices.filter {
                images[$0].isEnabled && images[$0].role == .alignment
            }
            let ring = ringIndices.map { images[$0] }
            let points = try OpenCVControlPointMatcher.ring(
                images: ring,
                horizontalFieldOfView: inputFieldOfView,
                lensProfile: lensProfile,
                nominalYaws: ring.indices.map {
                    Double($0) * 360 / Double(ring.count)
                }
            )
            print("PANOWIZARD_FOLDER_NOMINAL_RING_POINTS=\(points.count)")
            let groupedPoints = Dictionary(grouping: points, by: { point in
                ControlPointPair.ID(
                    firstImage: point.firstImage,
                    secondImage: point.secondImage
                )
            })
            for (pair, pairPoints) in groupedPoints.sorted(
                by: { $0.key < $1.key }
            ) {
                print(
                    "PANOWIZARD_FOLDER_NOMINAL_PAIR="
                        + "\(pair.firstImage + 1)-\(pair.secondImage + 1) "
                        + "points=\(pairPoints.count)"
                )
            }
            suppliedControlPoints = points.map { point in
                DiagnosticControlPoint(
                    firstImage: ringIndices[point.firstImage],
                    secondImage: ringIndices[point.secondImage],
                    firstX: point.firstX,
                    firstY: point.firstY,
                    secondX: point.secondX,
                    secondY: point.secondY
                )
            }
        } else if requestedPairs.isEmpty {
            suppliedControlPoints = nil
        } else {
            var generated: [DiagnosticControlPoint] = []
            for (first, second) in requestedPairs {
                let points = try OpenCVControlPointMatcher.pair(
                    images: images,
                    pair: ControlPointPair.ID(
                        firstImage: first,
                        secondImage: second
                    ),
                    horizontalFieldOfView: inputFieldOfView,
                    lensProfile: lensProfile
                )
                print(
                    "PANOWIZARD_FOLDER_MANUAL_PAIR="
                        + "\(first + 1)-\(second + 1) points=\(points.count)"
                )
                generated += points.map {
                    DiagnosticControlPoint(
                        firstImage: $0.firstImage,
                        secondImage: $0.secondImage,
                        firstX: $0.firstX,
                        firstY: $0.firstY,
                        secondX: $0.secondX,
                        secondY: $0.secondY
                    )
                }
            }
            suppliedControlPoints = generated
        }
        if environment[
            "PANOWIZARD_FOLDER_WIZARD_LAST_IS_NADIR_REPAIR"
        ] == "1", let last = project.images.indices.last {
            project.images[last].role = .fillOnly
            project.images[last].direction = .nadir
        }
        if let capturePath = environment[
            "PANOWIZARD_FOLDER_CAPTURE_POINTS_PROJECT"
        ] {
            project.controlPoints = suppliedControlPoints ?? []
            let captureEncoder = JSONEncoder()
            captureEncoder.dateEncodingStrategy = .iso8601
            captureEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try captureEncoder.encode(project).write(
                to: URL(fileURLWithPath: capturePath),
                options: .atomic
            )
        }
        let result: PanoramaStitchResult
        do {
            result = try await HuginOpenCVPanoramaEngine().stitch(
                project.panorama,
                masks: [:],
                protectedMasks: [:],
                controlPoints: suppliedControlPoints,
                controlPointsAreAuthoritative: environment[
                    "PANOWIZARD_FOLDER_WIZARD_POINTS"
                ] != "1" && environment[
                    "PANOWIZARD_FOLDER_POINTS_ARE_AUTOMATIC"
                ] != "1",
                configuration: configuration,
                cachedRigImageLines: [:]
            )
        } catch {
            for diagnostic in OpenCVControlPointMatcher.lastPairDiagnostics {
                print(
                    "PANOWIZARD_FOLDER_PAIR="
                        + "\(diagnostic.firstImage + 1)-"
                        + "\(diagnostic.secondImage + 1) "
                        + "selected=\(diagnostic.selectedControlPointCount) "
                        + "coverage="
                        + String(format: "%.3f", diagnostic.spatialCoverage)
                )
            }
            throw error
        }
        let resultURL = try #require(result.url)
        project.applyAutomaticPositioningDecisions(
            result.automaticPositioningDecisions
        )
        project.controlPoints = try #require(
            result.controlPointDiagnostics?.cleanedPoints
        )
        project.nadirRepairPlacement = result.nadirRepair?.placement
        project.zenithRepairPlacement = result.zenithRepair?.placement

        let output = URL(fileURLWithPath: outputPath)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let panoramaDirectory = output.appending(
            path: "panorama", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: panoramaDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(
            to: output.appending(path: "project.json"),
            options: .atomic
        )
        try FileManager.default.copyItem(
            at: resultURL,
            to: panoramaDirectory.appending(path: "result.jpg")
        )
        if let overlay = result.nadirRepair?.overlayURL {
            try FileManager.default.copyItem(
                at: overlay,
                to: panoramaDirectory.appending(path: "nadir-overlay.png")
            )
            if let placement = result.nadirRepair?.placement,
               let repairImage = project.images.first(where: {
                   $0.id == placement.imageID
               }) {
                try OpenCVNadirRepairRegistrar.renderBlendedOverlay(
                    panoramaURL: resultURL,
                    repairImage: repairImage,
                    exclusionMaskData: nil,
                    projectedRepairURL: overlay,
                    horizontalFieldOfView:
                        placement.sourceHorizontalFieldOfView
                            ?? configuration.inputHorizontalFieldOfView,
                    pole: .nadir,
                    placement: placement,
                    outputURL: panoramaDirectory.appending(
                        path: "nadir-blended-overlay.png"
                    )
                )
            }
        }
        if let overlay = result.zenithRepair?.overlayURL {
            try FileManager.default.copyItem(
                at: overlay,
                to: panoramaDirectory.appending(path: "zenith-overlay.png")
            )
        }
        print("PANOWIZARD_FOLDER_PROJECT=\(output.path)")
    }

    @Test
    func canonicalizesGloballyInvertedRing() {
        let orientations = [
            PanoramaOrientation(yaw: -151, pitch: 20, roll: -179.8),
            PanoramaOrientation(yaw: 115, pitch: 20, roll: -180),
            PanoramaOrientation(yaw: 30, pitch: 20, roll: -179.8),
            PanoramaOrientation(yaw: -63, pitch: 20, roll: -179.7),
            PanoramaOrientation(yaw: 1, pitch: -89.7, roll: 117.4)
        ]

        #expect(
            HuginOpenCVPanoramaEngine.needsUprightCanonicalization(
                orientations: orientations
            )
        )
    }

    @Test
    func preservesAlreadyUprightRing() {
        let orientations = [
            PanoramaOrientation(yaw: 160, pitch: -20, roll: -4.1),
            PanoramaOrientation(yaw: -106, pitch: -20, roll: -0.2),
            PanoramaOrientation(yaw: -21, pitch: -20, roll: 0.2),
            PanoramaOrientation(yaw: 72, pitch: -20, roll: 0.3),
            PanoramaOrientation(yaw: 8, pitch: 89.7, roll: -62.6)
        ]

        #expect(
            !HuginOpenCVPanoramaEngine.needsUprightCanonicalization(
                orientations: orientations
            )
        )
    }

    @Test
    func preservesWizardGeneratedNikonGraphBeforeBundleAdjustment() {
        #expect(
            HuginOpenCVPanoramaEngine.preservesSuppliedRingGraph(
                hasSuppliedControlPoints: true,
                isCircularFisheye: false
            )
        )
        #expect(
            !HuginOpenCVPanoramaEngine.preservesSuppliedRingGraph(
                hasSuppliedControlPoints: false,
                isCircularFisheye: false
            )
        )
        #expect(
            HuginOpenCVPanoramaEngine.preservesSuppliedRingGraph(
                hasSuppliedControlPoints: false,
                isCircularFisheye: true
            )
        )
    }

    @Test
    func isolatesOnlyDelayedFinalImageFromRedundantRig() {
        let lens = LensDescription(
            model: "Sigma 8 mm",
            focalLengthIn35mm: 8,
            kind: .fisheye
        )
        func images(finalGap: TimeInterval = 40) -> [SourceImage] {
            let times: [TimeInterval] = [0, 8, 15, 22, 27, 27 + finalGap]
            return times.enumerated().map { index, time in
                SourceImage(
                    url: URL(fileURLWithPath: "/Pictures/\(index).tif"),
                    captureDate: Date(timeIntervalSince1970: time),
                    pixelWidth: 2_600,
                    pixelHeight: 3_888,
                    cameraModel: "NIKON D80",
                    lens: lens
                )
            }
        }
        func point(_ first: Int, _ second: Int) -> PanoramaControlPoint {
            PanoramaControlPoint(
                firstImage: first,
                secondImage: second,
                firstX: 10,
                firstY: 20,
                secondX: 30,
                secondY: 40
            )
        }
        let cyclicRig = [
            point(0, 1), point(1, 2), point(2, 3),
            point(3, 4), point(4, 0)
        ]

        let accepted = HuginOpenCVPanoramaEngine
            .isolatedDelayedAutomaticRepairGraph(
                images: images(),
                controlPoints: cyclicRig
            )
        #expect(accepted?.candidate == 5)
        #expect(accepted?.rigIndices == [0, 1, 2, 3, 4])

        #expect(
            HuginOpenCVPanoramaEngine.isolatedDelayedAutomaticRepairGraph(
                images: images(finalGap: 8),
                controlPoints: cyclicRig
            ) == nil
        )
        #expect(
            HuginOpenCVPanoramaEngine.isolatedDelayedAutomaticRepairGraph(
                images: images(),
                controlPoints: Array(cyclicRig.dropLast())
            ) == nil
        )
        #expect(
            HuginOpenCVPanoramaEngine.isolatedDelayedAutomaticRepairGraph(
                images: images(),
                controlPoints: [point(0, 1), point(1, 2), point(2, 0)]
            ) == nil
        )
    }

    @Test
    func requiresBalancedSupportForLocalTwoImageRepair() {
        func supportingImages(_ counts: [Int]) -> [Int] {
            counts.enumerated().flatMap { image, count in
                Array(repeating: image, count: count)
            }
        }

        #expect(
            HuginOpenCVPanoramaEngine.hasBalancedTwoImageRepairSupport(
                supportingImages([4, 4])
            )
        )
        #expect(
            !HuginOpenCVPanoramaEngine.hasBalancedTwoImageRepairSupport(
                supportingImages([7, 1])
            )
        )
        #expect(
            !HuginOpenCVPanoramaEngine.hasBalancedTwoImageRepairSupport(
                supportingImages([4, 3])
            )
        )
    }

    @Test
    func strongLocalEvidenceCorrectsLargeAutomaticPoleRotationConflict() {
        func placement(
            matches: Int,
            homography: [Double]
        ) -> NadirRepairPlacement {
            NadirRepairPlacement(
                imageID: UUID(),
                localHomography: homography,
                matchedFeatureCount: matches,
                localViewFieldOfView: 120
            )
        }
        let spherical = placement(
            matches: 95,
            homography: [
                -1.1539, 0.5270, 1_120.2,
                -0.6859, -0.9958, 2_023.5,
                -0.00019, 0.00001, 1
            ]
        )
        let local = placement(
            matches: 3_142,
            homography: [
                0.3988, 0.8266, -238.8,
                -0.8946, 0.5942, 912.1,
                -0.00018, 0.00007, 1
            ]
        )

        #expect(
            HuginOpenCVPanoramaEngine.shouldPreferLocalRepairRegistration(
                local: local,
                spherical: spherical
            )
        )
        #expect(
            !HuginOpenCVPanoramaEngine.shouldPreferLocalRepairRegistration(
                local: placement(
                    matches: 200,
                    homography: local.localHomography
                ),
                spherical: spherical
            )
        )
        #expect(
            !HuginOpenCVPanoramaEngine.shouldPreferLocalRepairRegistration(
                local: placement(
                    matches: 3_142,
                    homography: spherical.localHomography
                ),
                spherical: spherical
            )
        )
    }

    @Test
    func removesCatastrophicSmallPairWithoutDiscardingNoisyBridge() {
        let stable = Self.points(first: 0, second: 1, count: 20)
        let noisyBridge = Self.points(first: 1, second: 2, count: 4)
        let falseExtraPair = Self.points(first: 0, second: 2, count: 4)
        let points = stable + noisyBridge + falseExtraPair
        let errors = Array(repeating: 1.0, count: stable.count)
            + [10, 12, 14, 16]
            + [1_100, 1_200, 1_300, 1_400]

        let accepted = HuginOpenCVPanoramaEngine.robustControlPoints(
            points,
            errors: errors
        )

        #expect(accepted.filter { $0.pair.firstImage == 1 }.count == 4)
        #expect(accepted.contains { $0.pair == falseExtraPair[0].pair } == false)
    }

    @Test
    func removesModerateParallaxTailFromDenseAutomaticPair() {
        let stable = Self.points(first: 0, second: 1, count: 30)
        let parallax = Self.points(first: 0, second: 1, count: 10)
        let points = stable + parallax
        let errors = Array(repeating: 1.0, count: stable.count)
            + Array(repeating: 7.0, count: parallax.count)

        let accepted = HuginOpenCVPanoramaEngine.robustControlPoints(
            points,
            errors: errors
        )

        #expect(accepted.count == stable.count)
    }

    @Test
    func alwaysUsesDistanceBasedSeams() {
        #expect(
            HuginOpenCVPanoramaEngine.primarySeamGenerator
                == "nearest-feature-transform"
        )
    }

    @Test
    func retriesOnlyPoorAutomaticGeometry() {
        #expect(
            HuginOpenCVPanoramaEngine.needsAutomaticStabilization(
                errors: [
                    0.8, 1, 1.2, 1.4, 2, 5, 9.9, 10, 15, 20,
                    25, 30, 32, 40, 60
                ]
            )
        )
        #expect(
            !HuginOpenCVPanoramaEngine.needsAutomaticStabilization(
                errors: [
                    0.4, 0.6, 0.8, 0.9, 1, 1.1, 1.3, 1.5, 1.8, 2,
                    2.3, 2.6, 3, 4, 5.6
                ]
            )
        )
    }

    @Test
    func automaticRecoveryPointsRemainEligibleForResidualFiltering() {
        #expect(
            HuginOpenCVPanoramaEngine.treatsSuppliedControlPointsAsEdited(
                hasSuppliedControlPoints: true,
                controlPointsAreAuthoritative: true,
                isAutomaticRecovery: false
            )
        )
        #expect(
            !HuginOpenCVPanoramaEngine.treatsSuppliedControlPointsAsEdited(
                hasSuppliedControlPoints: true,
                controlPointsAreAuthoritative: true,
                isAutomaticRecovery: true
            )
        )
    }

    @Test
    func authoritativeRerenderKeepsStoredAutomaticRepairDecision() throws {
        let lens = LensDescription(
            model: "Sigma 8 mm",
            focalLengthIn35mm: 8,
            kind: .fisheye
        )
        let images = (0..<6).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).tif"),
                captureDate: nil,
                pixelWidth: 2_600,
                pixelHeight: 3_888,
                cameraModel: "NIKON D80",
                lens: lens,
                role: .automatic,
                automaticRole: index == 5 ? .fillOnly : .alignment,
                automaticDirection: index == 5 ? .nadir : .horizontal
            )
        }

        let decisions = try #require(
            HuginOpenCVPanoramaEngine.storedAutomaticPositioningDecisions(
                images: images
            )
        )

        #expect(decisions.count == 6)
        #expect(decisions[images[5].id]?.role == .fillOnly)
        #expect(decisions[images[5].id]?.direction == .nadir)

        var incomplete = images
        incomplete[0].automaticRole = nil
        #expect(
            HuginOpenCVPanoramaEngine.storedAutomaticPositioningDecisions(
                images: incomplete
            ) == nil
        )
    }

    @Test
    func rejectsFourImageRingHeldTogetherByWeakFalsePair() {
        let points =
            Self.points(first: 0, second: 1, count: 23)
            + Self.points(first: 1, second: 2, count: 23)
            + Self.points(first: 1, second: 3, count: 5)

        #expect(
            HuginOpenCVPanoramaEngine.weakFourImageRingImages(
                controlPoints: points
            ) == [0, 1, 2, 3]
        )
    }

    @Test
    func acceptsFourImageRingWithTwoReliableNeighborsPerImage() {
        let points =
            Self.points(first: 0, second: 1, count: 12)
            + Self.points(first: 1, second: 2, count: 12)
            + Self.points(first: 2, second: 3, count: 12)
            + Self.points(first: 0, second: 3, count: 12)

        #expect(
            HuginOpenCVPanoramaEngine.weakFourImageRingImages(
                controlPoints: points
            ).isEmpty
        )
    }

    @Test
    func acceptsSparseFourImageTransitionWithLowGlobalResiduals() {
        let points =
            Self.points(first: 0, second: 1, count: 6, error: 0.75)
            + Self.points(first: 1, second: 2, count: 20, error: 0.8)
            + Self.points(first: 2, second: 3, count: 20, error: 0.9)
            + Self.points(first: 0, second: 3, count: 4, error: 1.1)

        #expect(
            HuginOpenCVPanoramaEngine.weakFourImageRingImages(
                controlPoints: points
            ).isEmpty
        )
    }

    @Test
    func rejectsSparseFourImageTransitionWithHighGlobalResiduals() {
        let points =
            Self.points(first: 0, second: 1, count: 6, error: 8)
            + Self.points(first: 1, second: 2, count: 20, error: 0.8)
            + Self.points(first: 2, second: 3, count: 20, error: 0.9)
            + Self.points(first: 0, second: 3, count: 4, error: 7)

        #expect(
            HuginOpenCVPanoramaEngine.weakFourImageRingImages(
                controlPoints: points
            ) == [0, 1, 2, 3]
        )
    }

    @Test
    func acceptsReliableClosureThroughSixRingImages() {
        let points =
            Self.points(first: 0, second: 1, count: 12)
            + Self.points(first: 1, second: 2, count: 12)
            + Self.points(first: 2, second: 3, count: 12)
            + Self.points(first: 3, second: 4, count: 12)
            + Self.points(first: 4, second: 5, count: 12)
            + Self.points(first: 0, second: 5, count: 12)

        #expect(
            HuginOpenCVPanoramaEngine.imagesOutsideReliableRingClosure(
                imageCount: 6,
                requiredImageIndices: Array(0..<6),
                controlPoints: points
            ).isEmpty
        )
    }

    @Test
    func rejectsConnectedSixImageRingWithoutClosure() {
        let points =
            Self.points(first: 0, second: 1, count: 12)
            + Self.points(first: 1, second: 2, count: 12)
            + Self.points(first: 2, second: 3, count: 12)
            + Self.points(first: 3, second: 4, count: 12)
            + Self.points(first: 4, second: 5, count: 12)

        #expect(
            HuginOpenCVPanoramaEngine.imagesOutsideReliableRingClosure(
                imageCount: 6,
                requiredImageIndices: Array(0..<6),
                controlPoints: points
            ) == Array(0..<6)
        )
    }

    @Test
    func allowsZenithLeafOutsideClosedHorizontalRing() {
        let points =
            Self.points(first: 0, second: 1, count: 12)
            + Self.points(first: 1, second: 2, count: 12)
            + Self.points(first: 2, second: 3, count: 12)
            + Self.points(first: 3, second: 4, count: 12)
            + Self.points(first: 4, second: 5, count: 12)
            + Self.points(first: 0, second: 5, count: 12)
            + Self.points(first: 2, second: 6, count: 12)

        #expect(
            HuginOpenCVPanoramaEngine.imagesOutsideReliableRingClosure(
                imageCount: 7,
                requiredImageIndices: Array(0..<6),
                controlPoints: points
            ).isEmpty
        )
    }

    @Test
    func allowsPoleAndOverlappingPositioningLeavesOutsideClosedBackbone() {
        let points =
            Self.points(first: 0, second: 1, count: 12, error: 0.8)
            + Self.points(first: 1, second: 2, count: 12, error: 0.8)
            + Self.points(first: 2, second: 3, count: 12, error: 0.8)
            + Self.points(first: 3, second: 4, count: 12, error: 0.8)
            + Self.points(first: 4, second: 5, count: 12, error: 0.8)
            + Self.points(first: 0, second: 5, count: 12, error: 0.8)
            + Self.points(first: 2, second: 6, count: 12, error: 0.8)
            + Self.points(first: 4, second: 7, count: 12, error: 0.8)
            + Self.points(first: 1, second: 8, count: 12, error: 0.8)
            + Self.points(first: 3, second: 9, count: 12, error: 0.8)
        let orientations = [
            PanoramaOrientation(yaw: 0, pitch: 4, roll: 0),
            PanoramaOrientation(yaw: 60, pitch: -12, roll: 0),
            PanoramaOrientation(yaw: 120, pitch: 35, roll: 0),
            PanoramaOrientation(yaw: 180, pitch: -25, roll: 0),
            PanoramaOrientation(yaw: -120, pitch: 18, roll: 0),
            PanoramaOrientation(yaw: -60, pitch: 6, roll: 0),
            PanoramaOrientation(yaw: 20, pitch: -88, roll: 0),
            PanoramaOrientation(yaw: -40, pitch: 89, roll: 0),
            PanoramaOrientation(yaw: 70, pitch: -87, roll: 0),
            PanoramaOrientation(yaw: 175, pitch: 2, roll: 0)
        ]

        #expect(
            HuginOpenCVPanoramaEngine.hasReliable360DegreeBackbone(
                orientations: orientations,
                horizontalFieldOfView: 87.44,
                controlPoints: points
            )
        )
    }

    @Test
    func rejectsLocalCycleWithOpenPositioningRemainder() {
        let points =
            Self.points(first: 0, second: 1, count: 12)
            + Self.points(first: 1, second: 2, count: 12)
            + Self.points(first: 0, second: 2, count: 12)
            + Self.points(first: 2, second: 3, count: 12)
            + Self.points(first: 3, second: 4, count: 12)
            + Self.points(first: 4, second: 5, count: 12)
        let orientations = [
            PanoramaOrientation(yaw: 0, pitch: 0, roll: 0),
            PanoramaOrientation(yaw: 45, pitch: 0, roll: 0),
            PanoramaOrientation(yaw: 90, pitch: 0, roll: 0),
            PanoramaOrientation(yaw: 150, pitch: 0, roll: 0),
            PanoramaOrientation(yaw: -150, pitch: 0, roll: 0),
            PanoramaOrientation(yaw: -60, pitch: 0, roll: 0)
        ]

        #expect(
            !HuginOpenCVPanoramaEngine.hasReliable360DegreeBackbone(
                orientations: orientations,
                horizontalFieldOfView: 87.44,
                controlPoints: points
            )
        )
    }

    @Test
    func rejectsDenseClosurePairWithHighOptimizedResiduals() {
        let points =
            Self.points(first: 0, second: 1, count: 12, error: 0.7)
            + Self.points(first: 1, second: 2, count: 12, error: 0.8)
            + Self.points(first: 2, second: 3, count: 12, error: 0.9)
            + Self.points(first: 3, second: 4, count: 12, error: 0.7)
            + Self.points(first: 4, second: 5, count: 12, error: 0.8)
            + Self.points(first: 0, second: 5, count: 12, error: 8)

        #expect(
            HuginOpenCVPanoramaEngine.imagesOutsideReliableRingClosure(
                imageCount: 6,
                requiredImageIndices: Array(0..<6),
                controlPoints: points
            ) == Array(0..<6)
        )
    }

    @Test
    func acceptsClosedRingWithModeratelyNoisyRealTransition() {
        let points =
            Self.points(first: 0, second: 1, count: 12, error: 0.7)
            + Self.points(first: 1, second: 2, count: 12, error: 0.8)
            + Self.points(first: 2, second: 3, count: 12, error: 0.9)
            + Self.points(first: 3, second: 4, count: 12, error: 4.5)
            + Self.points(first: 4, second: 5, count: 12, error: 0.8)
            + Self.points(first: 0, second: 5, count: 12, error: 0.9)

        #expect(
            HuginOpenCVPanoramaEngine.imagesOutsideReliableRingClosure(
                imageCount: 6,
                requiredImageIndices: Array(0..<6),
                controlPoints: points
            ).isEmpty
        )
    }

    private static func points(
        first: Int,
        second: Int,
        count: Int,
        error: Double? = nil
    ) -> [DiagnosticControlPoint] {
        (0..<count).map { index in
            DiagnosticControlPoint(
                firstImage: first,
                secondImage: second,
                firstX: Double(index),
                firstY: Double(index),
                secondX: Double(index),
                secondY: Double(index),
                error: error
            )
        }
    }

    @Test
    func rejectsFourImageRingWhosePointsOccupyOnlyANarrowBand() {
        let diagnostics = [
            Self.pairDiagnostic(0, 1, selected: 25, coverage: 0.33),
            Self.pairDiagnostic(1, 2, selected: 25, coverage: 0.29),
            Self.pairDiagnostic(2, 3, selected: 18, coverage: 0.08),
            Self.pairDiagnostic(0, 3, selected: 22, coverage: 0.25)
        ]

        #expect(
            OpenCVControlPointMatcher.weakFourImageRingPairs(
                in: diagnostics
            ).map { "\($0.0)-\($0.1)" } == ["2-3"]
        )
    }

    @Test
    func acceptsFourImageRingWithBroadCoverageOnEveryTransition() {
        let diagnostics = [
            Self.pairDiagnostic(0, 1, selected: 25, coverage: 0.29),
            Self.pairDiagnostic(1, 2, selected: 25, coverage: 0.38),
            Self.pairDiagnostic(2, 3, selected: 12, coverage: 0.38),
            Self.pairDiagnostic(0, 3, selected: 25, coverage: 0.33)
        ]

        #expect(
            OpenCVControlPointMatcher.weakFourImageRingPairs(
                in: diagnostics
            ).isEmpty
        )
    }

    @Test
    func acceptsDenseControlPointsInNarrowRealOverlap() {
        let diagnostics = [
            Self.pairDiagnostic(0, 1, selected: 25, coverage: 0.21),
            Self.pairDiagnostic(1, 2, selected: 25, coverage: 0.125),
            Self.pairDiagnostic(2, 3, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(0, 3, selected: 25, coverage: 0.29)
        ]

        #expect(
            OpenCVControlPointMatcher.weakFourImageRingPairs(
                in: diagnostics
            ).isEmpty
        )
    }

    @Test
    func identifiesWeakClosureInSixImageRingWithoutIncludingZenith() {
        let diagnostics = [
            Self.pairDiagnostic(0, 1, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(1, 2, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(2, 3, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(3, 4, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(4, 5, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(0, 5, selected: 7, coverage: 0.08),
            Self.pairDiagnostic(2, 6, selected: 5, coverage: 0.04)
        ]

        #expect(
            OpenCVControlPointMatcher.weakPositioningSequenceTransitions(
                in: diagnostics,
                positioningImageIndices: Array(0..<6)
            ).map { "\($0.0)-\($0.1)" } == ["0-5"]
        )
    }

    @Test
    func protectsOnlyWhenAWeakEdgeIsNeededForTheAvailableCycle() {
        let sparseCycle = [
            Self.pairDiagnostic(0, 1, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(1, 2, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(2, 3, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(3, 4, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(4, 5, selected: 25, coverage: 0.25),
            Self.pairDiagnostic(0, 5, selected: 7, coverage: 0.08),
            Self.pairDiagnostic(3, 6, selected: 12, coverage: 0.2)
        ]
        let redundantGraph = sparseCycle + [
            Self.pairDiagnostic(0, 2, selected: 25, coverage: 0.25)
        ]

        #expect(
            OpenCVControlPointMatcher.needsSparseCycleProtection(
                in: sparseCycle
            )
        )
        #expect(
            !OpenCVControlPointMatcher.needsSparseCycleProtection(
                in: redundantGraph
            )
        )
    }

    @Test
    func identifiesWeakExtraPairForDeferredBundleAssessment() {
        let diagnostics = [
            Self.pairDiagnostic(0, 1, selected: 25, coverage: 0.29),
            Self.pairDiagnostic(0, 2, selected: 6, coverage: 0.125),
            Self.pairDiagnostic(0, 3, selected: 25, coverage: 0.33),
            Self.pairDiagnostic(1, 2, selected: 25, coverage: 0.38),
            Self.pairDiagnostic(1, 4, selected: 25, coverage: 0.33),
            Self.pairDiagnostic(2, 3, selected: 12, coverage: 0.38),
            Self.pairDiagnostic(2, 4, selected: 25, coverage: 0.29),
            Self.pairDiagnostic(3, 4, selected: 25, coverage: 0.42)
        ]

        #expect(
            OpenCVControlPointMatcher.weakWideFisheyePairs(
                in: diagnostics
            ).map { "\($0.0)-\($0.1)" } == ["0-2"]
        )
    }

    private static func pairDiagnostic(
        _ first: Int,
        _ second: Int,
        selected: Int,
        coverage: Double
    ) -> ControlPointPairGenerationDiagnostic {
        ControlPointPairGenerationDiagnostic(
            firstImage: first,
            secondImage: second,
            firstFeatureCount: 5_000,
            secondFeatureCount: 5_000,
            ratioMatchCount: 800,
            mutualMatchCount: 500,
            geometricMatchCount: 300,
            selectedControlPointCount: selected,
            meanReprojectionError: 0,
            spatialCoverage: coverage
        )
    }

    @Test
    func rectangularMaskFillsOnlyDraggedArea() throws {
        let data = try #require(SourceMaskRasterizer.applyingRectangle(
            from: MaskPoint(x: 0.2, y: 0.25),
            to: MaskPoint(x: 0.7, y: 0.75),
            erasing: false,
            to: nil,
            width: 200,
            height: 100
        ))
        let mask = try #require(SourceMaskRasterizer.exclusionMap(
            from: data, width: 200, height: 100
        ))
        #expect(mask.contains(CGPoint(x: 100, y: 50), safetyRadius: 0))
        #expect(!mask.contains(CGPoint(x: 20, y: 50), safetyRadius: 0))
        #expect(!mask.contains(CGPoint(x: 180, y: 50), safetyRadius: 0))
    }

    @Test
    func eraserRemovesPaintInsteadOfAddingIt() throws {
        let painted = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)], radius: 30,
            erasing: false, to: nil, width: 100, height: 100
        ))
        let erased = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)], radius: 12,
            erasing: true, to: painted, width: 100, height: 100
        ))
        let mask = try #require(SourceMaskRasterizer.exclusionMap(
            from: erased, width: 100, height: 100
        ))
        #expect(!mask.contains(CGPoint(x: 50, y: 50), safetyRadius: 0))
        #expect(mask.contains(CGPoint(x: 75, y: 50), safetyRadius: 0))
    }

    @Test
    func erasingAnEmptyMaskDoesNotCreateTransparentMaskData() {
        let result = SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)], radius: 12,
            erasing: true, to: nil, width: 100, height: 100
        )
        #expect(result == nil)
    }

    @Test
    func circularMaskStaysCircularOnLandscapeImages() throws {
        let width = 300
        let height = 100
        let data = try #require(SourceMaskRasterizer.applyingCircle(
            center: MaskPoint(x: 0.5, y: 0.5),
            radius: 25,
            erasing: false,
            to: nil,
            width: width,
            height: height
        ))
        let mask = try #require(SourceMaskRasterizer.exclusionMap(
            from: data,
            width: width,
            height: height
        ))

        #expect(mask.contains(CGPoint(x: 150, y: 50), safetyRadius: 0))
        #expect(mask.contains(CGPoint(x: 174, y: 50), safetyRadius: 0))
        #expect(mask.contains(CGPoint(x: 150, y: 74), safetyRadius: 0))
        #expect(!mask.contains(CGPoint(x: 176, y: 50), safetyRadius: 0))
        #expect(!mask.contains(CGPoint(x: 150, y: 76), safetyRadius: 0))
    }

    @Test
    func exportsSelfContainedInteractiveHTML() async throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }
        let package = URL(fileURLWithPath: packagePath)
        let panoramaURL = package.appending(path: "panorama/result.jpg")
        guard FileManager.default.fileExists(atPath: panoramaURL.path) else {
            return
        }
        let overlayURL = package.appending(path: "panorama/nadir-overlay.png")
        let zenithOverlayURL = package.appending(
            path: "panorama/zenith-overlay.png"
        )
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-panorama.html"
        )

        try await FilePanoramaExporter().exportHTML(
            panoramaURL: panoramaURL,
            nadirOverlayURL: FileManager.default.fileExists(
                atPath: overlayURL.path
            ) ? overlayURL : nil,
            zenithOverlayURL: FileManager.default.fileExists(
                atPath: zenithOverlayURL.path
            ) ? zenithOverlayURL : nil,
            nadirRetouchURL: nil,
            zenithRetouchURL: nil,
            title: "Pano <Wizard>",
            initialViewpoint: PanoramaViewpoint(
                yawRadians: 0.42,
                pitchRadians: -0.17,
                verticalFieldOfViewDegrees: 61
            ),
            to: outputURL
        )

        let html = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(html.contains("<html lang=\"en\">"))
        #expect(html.contains("<title>Pano &lt;Wizard&gt;</title>"))
        #expect(!html.contains("<div id=\"controls\">"))
        #expect(!html.contains("Drag to look around"))
        #expect(!html.contains("Dra för att"))
        #expect(html.contains("data:image/jpeg;base64,"))
        #expect(html.contains("getContext(\"webgl\")"))
        #expect(html.contains("zenithRepair"))
        #expect(html.contains("nadirRetouch"))
        #expect(html.contains("zenithRetouch"))
        #expect(html.contains("let y=0.42,"))
        #expect(html.contains("p=-0.17,"))
        #expect(html.contains("f=61.0*PI/180"))
        #expect((try Data(contentsOf: outputURL)).count > 100_000)
        print("PANOWIZARD_HTML_EXPORT=\(outputURL.path)")
    }

    @Test
    func blendsRepairIntoFrozenLocalPanoramaView() throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }

        let package = URL(fileURLWithPath: packagePath)
        let project = try PanoProjectDocument(contentsOf: package).project
        let placement = try #require(project.nadirRepairPlacement)
        let repairImage = try #require(
            project.images.first { $0.id == placement.imageID }
        )
        let panoramaURL = package.appending(path: "panorama/result.jpg")
        let maskURL = package.appending(
            path: "masks/\(repairImage.id.uuidString).png"
        )
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-blended-nadir-overlay.png"
        )

        try OpenCVNadirRepairRegistrar.renderBlendedOverlay(
            panoramaURL: panoramaURL,
            repairImage: repairImage,
            exclusionMaskData: try? Data(contentsOf: maskURL),
            horizontalFieldOfView:
                project.stitching.inputHorizontalFieldOfView,
            placement: placement,
            outputURL: outputURL
        )

        let imageSource = try #require(
            CGImageSourceCreateWithURL(outputURL as CFURL, nil)
        )
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(
                imageSource,
                0,
                nil
            ) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1_600)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1_600)
        #expect((try Data(contentsOf: outputURL)).count > 100_000)
        print("PANOWIZARD_BLENDED_NADIR=\(outputURL.path(percentEncoded: false))")
    }

    @Test
    func blendsZenithRepairIntoFrozenLocalPanoramaView() throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else { return }
        let package = URL(fileURLWithPath: packagePath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(
            PanoProject.self,
            from: Data(contentsOf: package.appending(path: "project.json"))
        )
        let placement = try #require(project.zenithRepairPlacement)
        let repairImage = try #require(
            project.images.first { $0.id == placement.imageID }
        )
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-blended-zenith-overlay.png"
        )
        try OpenCVNadirRepairRegistrar.renderBlendedOverlay(
            panoramaURL: package.appending(path: "panorama/result.jpg"),
            repairImage: repairImage,
            exclusionMaskData: try? Data(contentsOf: package.appending(
                path: "masks/\(repairImage.id.uuidString).png"
            )),
            horizontalFieldOfView:
                project.stitching.inputHorizontalFieldOfView,
            pole: .zenith,
            placement: placement,
            outputURL: outputURL
        )
        #expect((try Data(contentsOf: outputURL)).count > 100_000)
        print("PANOWIZARD_BLENDED_ZENITH=\(outputURL.path)")
    }

    @Test
    func rendersRepairSelectionWithoutRebuildingPanorama() throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }

        let package = URL(fileURLWithPath: packagePath)
        let project = try PanoProjectDocument(contentsOf: package).project
        let placement = try #require(project.nadirRepairPlacement)
        let repairImage = try #require(
            project.images.first { $0.id == placement.imageID }
        )
        let paintedSelection = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)],
            radius: 180,
            erasing: false,
            to: nil,
            width: repairImage.pixelWidth,
            height: repairImage.pixelHeight
        ))
        let selectionMask = try #require(SourceMaskRasterizer.inverted(
            paintedSelection,
            width: repairImage.pixelWidth,
            height: repairImage.pixelHeight
        ))
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-masked-nadir-overlay.png"
        )

        try OpenCVNadirRepairRegistrar.renderOverlay(
            repairImage: repairImage,
            exclusionMaskData: selectionMask,
            horizontalFieldOfView:
                project.stitching.inputHorizontalFieldOfView,
            placement: placement,
            outputURL: outputURL
        )

        let imageSource = try #require(
            CGImageSourceCreateWithURL(outputURL as CFURL, nil)
        )
        let image = try #require(
            CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        )
        var alpha = [UInt8](
            repeating: 0,
            count: image.width * image.height * 4
        )
        let rendered = alpha.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: image.width,
                    height: image.height
                )
            )
            return true
        }

        #expect(rendered)
        let alphaValues = stride(from: 3, to: alpha.count, by: 4).map {
            alpha[$0]
        }
        #expect(alphaValues.contains(0))
        #expect(alphaValues.contains { $0 > 0 })
    }

    @Test
    func stitchesConfiguredProjectWhenRequested() async throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }

        let package = URL(fileURLWithPath: packagePath)
        let document = try PanoProjectDocument(contentsOf: package)
        var project = document.project
        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_MARK_LAST_ALIGNMENT_ZENITH"
        ] == "1", let index = project.images.lastIndex(where: {
            $0.isEnabled && $0.role == .alignment
        }) {
            project.images[index].direction = .zenith
        }
        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_MARK_LAST_AS_NADIR_REPAIR"
        ] == "1", let last = project.images.indices.last {
            project.images[last].role = .fillOnly
            project.images[last].direction = .nadir
        }
        let masks = document.masks
        var configuration = project.stitching
        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_FORCE_AUTOMATIC_ENGINE"
        ] == "1" {
            configuration.engine = .automatic
        }
        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_OPTIMIZE_ONLY"
        ] == "1" {
            let points = try #require(project.controlPoints)
            let optimized = try await HuginOpenCVPanoramaEngine()
                .optimizeControlPoints(
                    project.panorama,
                    controlPoints: points,
                    controlPointsAreAuthoritative: true,
                    configuration: configuration
                )
            #expect(!optimized.diagnostics.cleanedPoints.isEmpty)
            #expect(optimized.diagnostics.cleanedPoints.count <= points.count)
            #expect(
                optimized.diagnostics.cleanedPoints.allSatisfy {
                    $0.error?.isFinite == true
                }
            )
            let errors = optimized.diagnostics.cleanedPoints.compactMap(\.error)
            print(
                "PANOWIZARD_CONTROL_POINT_ERRORS="
                    + errors.map { String(format: "%.3f", $0) }
                        .joined(separator: ",")
            )
            let worst = optimized.diagnostics.cleanedPoints.enumerated()
                .sorted {
                    ($0.element.error ?? 0) > ($1.element.error ?? 0)
                }
                .prefix(10)
                .map {
                    let point = $0.element
                    return "\($0.offset + 1):"
                        + "\(point.firstImage + 1)-\(point.secondImage + 1)="
                        + String(format: "%.3f", point.error ?? 0)
                }
            print("PANOWIZARD_WORST_CONTROL_POINTS=\(worst.joined(separator: ","))")
            return
        }
        let regenerateControlPoints = ProcessInfo.processInfo.environment[
            "PANOWIZARD_REGENERATE_CONTROL_POINTS"
        ] == "1"
        var protectedMasks: [UUID: Data] = [:]
        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_VERIFY_PROTECTED_MASKS"
        ] == "1", let image = project.images.first(where: {
            $0.isEnabled && $0.role == .alignment
        }) {
            protectedMasks[image.id] = SourceMaskRasterizer.applyingCircle(
                center: MaskPoint(x: 0.5, y: 0.5),
                radius: 120,
                erasing: false,
                protectedArea: true,
                to: nil,
                width: image.pixelWidth,
                height: image.pixelHeight
            )
        }
        let result = try await HuginOpenCVPanoramaEngine().stitch(
            project.panorama,
            masks: masks,
            protectedMasks: protectedMasks,
            controlPoints: regenerateControlPoints ? nil : project.controlPoints,
            controlPointsAreAuthoritative: !regenerateControlPoints,
            configuration: configuration,
            cachedRigImageLines: [:]
        )
        let resultURL = try #require(result.url)

        #expect(FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)))
        #expect((try Data(contentsOf: resultURL)).count > 100_000)
        #expect(
            result.controlPointDiagnostics?.cleanedPoints.allSatisfy {
                $0.error?.isFinite != false
            } == true
        )
        print("PANOWIZARD_INTEGRATION_RESULT=\(resultURL.path(percentEncoded: false))")

        if let outputPath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_OUTPUT_PROJECT"
        ] {
            let outputPackage = URL(fileURLWithPath: outputPath)
            guard !FileManager.default.fileExists(atPath: outputPackage.path)
            else {
                throw CocoaError(.fileWriteFileExists)
            }
            var savedProject = project
            savedProject.id = UUID()
            savedProject.title = "PanoWizard sfärisk ring"
            savedProject.createdAt = .now
            savedProject.modifiedAt = .now
            savedProject.controlPoints = try #require(
                result.controlPointDiagnostics?.cleanedPoints
            )
            if !result.rigImageLines.isEmpty {
                savedProject.cachedRigImageLines = Dictionary(
                    uniqueKeysWithValues: result.rigImageLines.map {
                        ($0.key.uuidString, $0.value)
                    }
                )
                savedProject.cachedRigSignature = savedProject.rigSignature
            }
            try FileManager.default.createDirectory(
                at: outputPackage.appending(
                    path: "panorama", directoryHint: .isDirectory
                ),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(savedProject).write(
                to: outputPackage.appending(path: "project.json"),
                options: .atomic
            )
            try FileManager.default.copyItem(
                at: resultURL,
                to: outputPackage.appending(path: "panorama/result.jpg")
            )
            print("PANOWIZARD_INTEGRATION_PROJECT=\(outputPackage.path)")
        }

        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_VERIFY_CONTROL_POINT_EDITING"
        ] == "1" {
            let editedPoints = try #require(
                result.controlPointDiagnostics?.cleanedPoints
            )
            let editedResult = try await HuginOpenCVPanoramaEngine()
                .optimizeControlPoints(
                project.panorama,
                controlPoints: editedPoints,
                controlPointsAreAuthoritative: true,
                configuration: configuration
            )
            #expect(
                editedResult.diagnostics.cleanedPoints.count
                    == editedPoints.count
            )
            #expect(
                editedResult.diagnostics.cleanedPoints.allSatisfy {
                    $0.error?.isFinite == true
                }
            )
            print("PANOWIZARD_CONTROL_POINT_OPTIMIZATION=complete")
        }

        if let repairImage = project.images.first(where: {
            $0.effectiveRole == .fillOnly && $0.effectiveDirection == .nadir
        }) {
            let repair = try #require(result.nadirRepair)
            #expect(repair.placement.imageID == repairImage.id)
            #expect(repair.placement.localHomography.count == 9)
            #expect(repair.placement.matchedFeatureCount >= 12)
            #expect(
                FileManager.default.fileExists(
                    atPath: repair.overlayURL.path(percentEncoded: false)
                )
            )
            #expect((try Data(contentsOf: repair.overlayURL)).count > 100_000)
            let imageSource = try #require(
                CGImageSourceCreateWithURL(
                    repair.overlayURL as CFURL,
                    nil
                )
            )
            let properties = try #require(
                CGImageSourceCopyPropertiesAtIndex(
                    imageSource,
                    0,
                    nil
                ) as? [CFString: Any]
            )
            #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1_600)
            #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1_600)
            let homographyDescription = repair.placement.localHomography
                .map { String($0) }
                .joined(separator: ",")
            print(
                "PANOWIZARD_NADIR_OVERLAY=\(repair.overlayURL.path(percentEncoded: false)) "
                    + "matches=\(repair.placement.matchedFeatureCount) "
                    + "homography=\(homographyDescription)"
            )
            if ProcessInfo.processInfo.environment[
                "PANOWIZARD_COMPARE_LOCAL_REPAIR"
            ] == "1" {
                let localOverlay = resultURL.deletingLastPathComponent()
                    .appending(path: "nadir-overlay-local.png")
                let local = try OpenCVNadirRepairRegistrar.register(
                    panoramaURL: resultURL,
                    repairImage: repairImage,
                    exclusionMaskData: masks[repairImage.id],
                    horizontalFieldOfView:
                        repair.placement.sourceHorizontalFieldOfView
                            ?? configuration.inputHorizontalFieldOfView,
                    pole: .nadir,
                    outputURL: localOverlay
                )
                let localHomography = local.placement.localHomography
                    .map { String($0) }
                    .joined(separator: ",")
                print(
                    "PANOWIZARD_LOCAL_NADIR_OVERLAY="
                        + "\(local.overlayURL.path(percentEncoded: false)) "
                        + "matches=\(local.placement.matchedFeatureCount) "
                        + "homography=\(localHomography)"
                )
            }
        } else {
            #expect(result.nadirRepair?.overlayURL == nil)
        }
    }
}
