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
        let imported = await ImageImportService(
            metadataReader: ImageMetadataReader()
        ).load(from: [source])
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
        if usesNominalRing {
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
        let result: PanoramaStitchResult
        do {
            result = try await HuginOpenCVPanoramaEngine().stitch(
                project.panorama,
                masks: [:],
                protectedMasks: [:],
                controlPointMasks: [:],
                controlPoints: suppliedControlPoints,
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
    func rejectsFourImageRingHeldTogetherByWeakFalsePair() {
        let points =
            Self.points(first: 0, second: 1, count: 23)
            + Self.points(first: 1, second: 2, count: 23)
            + Self.points(first: 1, second: 3, count: 5)

        #expect(
            HuginOpenCVPanoramaEngine.weakFourImageRingImages(
                controlPoints: points
            ) == [0, 2, 3]
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
            ) == [0, 1, 3]
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
    func removesWeakExtraPairFromFiveImageWideFisheyeSet() {
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
            title: "Pano <Wizard>",
            initialViewpoint: PanoramaViewpoint(
                yawRadians: 0.42,
                pitchRadians: -0.17,
                verticalFieldOfViewDegrees: 61
            ),
            to: outputURL
        )

        let html = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(html.contains("<title>Pano &lt;Wizard&gt;</title>"))
        #expect(html.contains("data:image/jpeg;base64,"))
        #expect(html.contains("getContext(\"webgl\")"))
        #expect(html.contains("zenithRepair"))
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
        let projectData = try Data(
            contentsOf: package.appending(path: "project.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(PanoProject.self, from: projectData)
        var placement = try #require(project.nadirRepairPlacement)
        var adjustment = placement.manualAdjustment ?? .identity
        adjustment.cornerOffsets = [
            -4, 3,
            5, -2,
            6, 4,
            -3, 5
        ]
        placement.manualAdjustment = adjustment
        placement.contentBounds =
            OpenCVNadirRepairRegistrar.alphaContentBounds(
                at: package.appending(path: "panorama/nadir-overlay.png")
            ) ?? [0.2, 0.2, 0.6, 0.6]
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
        let projectData = try Data(
            contentsOf: package.appending(path: "project.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(PanoProject.self, from: projectData)
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
        let projectData = try Data(
            contentsOf: package.appending(path: "project.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var project = try decoder.decode(PanoProject.self, from: projectData)
        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_MARK_LAST_ALIGNMENT_ZENITH"
        ] == "1", let index = project.images.lastIndex(where: {
            $0.isEnabled && $0.role == .alignment
        }) {
            project.images[index].direction = .zenith
        }
        let masksDirectory = package.appending(
            path: "masks",
            directoryHint: .isDirectory
        )
        var masks: [UUID: Data] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(
            at: masksDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension.lowercased() == "png" {
                guard let id = UUID(
                    uuidString: file.deletingPathExtension().lastPathComponent
                ) else {
                    continue
                }
                masks[id] = try Data(contentsOf: file)
            }
        }
        let controlPointMasksDirectory = package.appending(
            path: "control-point-masks",
            directoryHint: .isDirectory
        )
        var controlPointMasks: [UUID: Data] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(
            at: controlPointMasksDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension.lowercased() == "png" {
                guard let id = UUID(
                    uuidString: file.deletingPathExtension().lastPathComponent
                ) else {
                    continue
                }
                controlPointMasks[id] = try Data(contentsOf: file)
            }
        }
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
                    controlPointMasks: controlPointMasks,
                    controlPoints: points,
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
            controlPointMasks: controlPointMasks,
            controlPoints: regenerateControlPoints ? nil : project.controlPoints,
            configuration: configuration,
            cachedRigImageLines: [:]
        )
        let resultURL = try #require(result.url)

        #expect(FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)))
        #expect((try Data(contentsOf: resultURL)).count > 100_000)
        #expect(
            result.controlPointDiagnostics?.cleanedPoints.allSatisfy {
                $0.error?.isFinite == true
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
                controlPointMasks: controlPointMasks,
                controlPoints: editedPoints,
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
            $0.role == .fillOnly && $0.direction == .nadir
        }) {
            let repair = try #require(result.nadirRepair)
            #expect(repair.placement.imageID == repairImage.id)
            #expect(repair.placement.localHomography.count == 9)
            #expect(repair.placement.matchedFeatureCount >= 12)
            #expect(repair.placement.contentBounds?.count == 4)
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
        } else {
            #expect(result.nadirRepair?.overlayURL == nil)
        }
    }
}
