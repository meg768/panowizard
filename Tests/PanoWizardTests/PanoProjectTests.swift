import Foundation
import Testing
@testable import PanoWizard

struct PanoProjectTests {
    @Test @MainActor
    func sourceDirectoryUsesTheImportedImageFolder() {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/Lissabon/one.jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: LensDescription(
                model: "Fisheye",
                focalLengthIn35mm: 16,
                kind: .fisheye
            )
        )
        let model = AppModel.live(project: PanoProject(images: [image]))

        #expect(
            model.sourceDirectoryURL?.path
                == URL(fileURLWithPath: "/Pictures/Lissabon").path
        )
    }

    @Test @MainActor
    func panoramaPreviewDoesNotFallBackToASourceImage() {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/source.jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: LensDescription(
                model: "Fisheye",
                focalLengthIn35mm: 16,
                kind: .fisheye
            )
        )
        let model = AppModel.live(project: PanoProject(images: [image]))

        model.selection = .panorama

        #expect(model.selectedPreviewURL == nil)
    }

    @Test
    func documentStoresPoleRetouchesInsidePanoramaDirectory() throws {
        let nadirRetouch = Data([1, 2, 3, 4])
        let zenithRetouch = Data([5, 6, 7, 8])
        let document = PanoProjectDocument(
            nadirRetouchData: nadirRetouch,
            zenithRetouchData: zenithRetouch
        )
        let wrapper = try document.packageFileWrapper()

        let stored = wrapper.fileWrappers?["panorama"]?
            .fileWrappers?["nadir-retouch.png"]?
            .regularFileContents
        let storedZenith = wrapper.fileWrappers?["panorama"]?
            .fileWrappers?["zenith-retouch.png"]?
            .regularFileContents
        #expect(stored == nadirRetouch)
        #expect(storedZenith == zenithRetouch)
        #expect(wrapper.fileWrappers?["control-point-masks"] == nil)
    }

    @Test
    func documentStoresAIRetouchPromptsInProjectJSON() throws {
        let project = PanoProject(
            nadirAIRetouchPrompt: "Behåll stolarna",
            zenithAIRetouchPrompt: "Behåll takkronan"
        )
        let wrapper = try PanoProjectDocument(project: project)
            .packageFileWrapper()
        let data = try #require(
            wrapper.fileWrappers?["project.json"]?.regularFileContents
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let storedProject = try decoder.decode(PanoProject.self, from: data)

        #expect(storedProject.nadirAIRetouchPrompt == "Behåll stolarna")
        #expect(storedProject.zenithAIRetouchPrompt == "Behåll takkronan")
    }

    @Test
    func atomicDocumentSaveReplacesTheEntireProjectPackage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let projectURL = directory.appending(
            path: "Test.pw",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let maskID = UUID()
        try PanoProjectDocument(
            masks: [maskID: Data([1, 2, 3])],
            panoramaData: Data([4, 5, 6])
        ).writeAtomically(to: projectURL)
        try PanoProjectDocument().writeAtomically(to: projectURL)

        let stored = try FileWrapper(url: projectURL)
        #expect(stored.fileWrappers?["project.json"] != nil)
        #expect(stored.fileWrappers?["masks"]?.fileWrappers?.isEmpty == true)
        #expect(stored.fileWrappers?["panorama"] == nil)
    }

    @Test
    func documentUsesRelativePathsAndDropsMissingSourceImages() throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let originalDirectory = container.appending(
            path: "Original",
            directoryHint: .isDirectory
        )
        let movedDirectory = container.appending(
            path: "Moved",
            directoryHint: .isDirectory
        )
        let sourceDirectory = originalDirectory.appending(
            path: "Sources",
            directoryHint: .isDirectory
        )
        let projectURL = originalDirectory.appending(
            path: "Test.pw",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: container) }

        let existingURL = sourceDirectory.appending(path: "one image.tif")
        let missingURL = sourceDirectory.appending(path: "missing.tif")
        try Data([1, 2, 3]).write(to: existingURL)
        let lens = LensDescription(
            model: "Fisheye",
            focalLengthIn35mm: 16,
            kind: .fisheye
        )
        let existing = SourceImage(
            url: existingURL,
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: lens
        )
        let missing = SourceImage(
            url: missingURL,
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: lens
        )
        let point = DiagnosticControlPoint(
            firstImage: 0,
            secondImage: 1,
            firstX: 10,
            firstY: 20,
            secondX: 30,
            secondY: 40
        )
        let document = PanoProjectDocument(
            project: PanoProject(
                images: [existing, missing],
                cachedRigImageLines: [
                    existing.id.uuidString:
                        "i w100 h100 n\"\(existingURL.path)\""
                ],
                controlPoints: [point]
            ),
            masks: [
                existing.id: Data([4]),
                missing.id: Data([5])
            ],
            protectedMasks: [
                existing.id: Data([6]),
                missing.id: Data([7])
            ]
        )
        try document.writeAtomically(to: projectURL)

        let projectData = try Data(
            contentsOf: projectURL.appending(path: "project.json")
        )
        let projectJSON = try #require(String(data: projectData, encoding: .utf8))
        #expect(!projectJSON.contains(container.path))
        #expect(!projectJSON.contains("file://"))
        #expect(projectJSON.contains("Sources/one%20image.tif"))
        #expect(projectJSON.contains("n\\\"Sources/one image.tif\\\""))

        try FileManager.default.moveItem(
            at: originalDirectory,
            to: movedDirectory
        )
        let movedProjectURL = movedDirectory.appending(
            path: "Test.pw",
            directoryHint: .isDirectory
        )
        let loaded = try PanoProjectDocument(contentsOf: movedProjectURL)

        #expect(loaded.project.images.count == 1)
        #expect(
            loaded.project.images[0].url.standardizedFileURL
                == movedDirectory.appending(path: "Sources/one image.tif")
                    .standardizedFileURL
        )
        #expect(loaded.project.controlPoints == nil)
        #expect(loaded.masks == [existing.id: Data([4])])
        #expect(loaded.protectedMasks == [existing.id: Data([6])])
    }

    @Test
    func documentLoadsAllPackageAssetsDirectlyFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let projectURL = directory.appending(
            path: "Test.pw",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let panorama = Data(repeating: 7, count: 2_000_000)
        let overlay = Data(repeating: 8, count: 3_000_000)
        try PanoProjectDocument(
            panoramaData: panorama,
            nadirOverlayData: overlay
        ).writeAtomically(to: projectURL)

        let loaded = try PanoProjectDocument(contentsOf: projectURL)
        #expect(loaded.panoramaData == panorama)
        #expect(loaded.nadirOverlayData == overlay)
    }

    @Test @MainActor
    func jpegExifLensModelOverridesIncorrectSavedProfile() {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/nikon.jpg"),
            captureDate: nil,
            pixelWidth: 2_000,
            pixelHeight: 3_008,
            cameraModel: "NIKON D70",
            lens: LensDescription(
                model: "AF DX Fisheye-Nikkor 10.5mm f/2.8G ED",
                focalLengthIn35mm: 10.5,
                kind: .fisheye
            )
        )
        let model = AppModel.live(project: PanoProject(
            images: [image],
            stitching: StitchingConfiguration(
                engine: .automatic,
                projection: .automatic,
                lensProfile: .sigma8DX,
                inputHorizontalFieldOfView: 165.38
            ),
            cachedRigImageLines: [image.id.uuidString: "i cached"],
            cachedRigSignature: "sigma-rig"
        ))

        #expect(model.project.stitching.lensProfile == .nikon105DX)
        #expect(model.project.stitching.inputHorizontalFieldOfView == 87.44)
        #expect(model.project.cachedRigImageLines == nil)
        #expect(model.project.cachedRigSignature == nil)
        #expect(model.imageMetadataLensProfile == .nikon105DX)
    }

    @Test @MainActor
    func legacyJPEGFocalLengthSelectsNikonProfileWithoutLensName() {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/nikon.jpg"),
            captureDate: nil,
            pixelWidth: 2_000,
            pixelHeight: 3_008,
            cameraModel: "NIKON D70",
            lens: LensDescription(
                model: "Fisheye (identifierat från bilden)",
                focalLengthIn35mm: 10.5,
                kind: .fisheye
            )
        )
        let model = AppModel.live(project: PanoProject(images: [image]))

        #expect(model.project.stitching.lensProfile == .nikon105DX)
        #expect(model.project.stitching.inputHorizontalFieldOfView == 87.44)
    }

    @Test @MainActor
    func optimizationDiagnosticsNeverDeleteEditedControlPoints() {
        let lens = LensDescription(
            model: "Fisheye", focalLengthIn35mm: 16, kind: .fisheye
        )
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 100,
                pixelHeight: 100,
                cameraModel: nil,
                lens: lens
            )
        }
        let first = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 10, firstY: 10, secondX: 20, secondY: 20
        )
        let second = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 30, firstY: 30, secondX: 40, secondY: 40
        )
        let model = AppModel.live(project: PanoProject(
            images: images,
            controlPoints: [first, second]
        ))
        let reported = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 10, firstY: 10, secondX: 20, secondY: 20,
            error: 1.5
        )

        model.applyOptimizationDiagnostics(
            ControlPointDiagnostics(
                images: images,
                rawPoints: [reported],
                cleanedPoints: [reported]
            ),
            preserving: [first, second]
        )

        #expect(model.editableControlPoints.count == 2)
        #expect(model.editableControlPoints.map(\.id) == [first.id, second.id])
        #expect(model.editableControlPoints[0].error == 1.5)
    }

    @Test
    func disablingImagePreservesItsControlPoints() {
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 100,
                pixelHeight: 100,
                cameraModel: "Camera",
                lens: LensDescription(
                    model: "Fisheye",
                    focalLengthIn35mm: 16,
                    kind: .fisheye
                )
            )
        }
        let point = DiagnosticControlPoint(
            firstImage: 0,
            secondImage: 1,
            firstX: 10,
            firstY: 20,
            secondX: 30,
            secondY: 40
        )
        var project = PanoProject(images: images, controlPoints: [point])

        project.toggleImageEnabled(images[1].id)

        #expect(project.images[1].isEnabled == false)
        #expect(project.controlPoints == [point])
        project.toggleImageEnabled(images[1].id)
        #expect(project.images[1].isEnabled == true)
        #expect(project.controlPoints == [point])
    }

    @Test
    func insertingAndReimportingImagesKeepsControlPointsWithTheirFiles() {
        let lens = LensDescription(
            model: "Fisheye",
            focalLengthIn35mm: 16,
            kind: .fisheye
        )
        let first = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/first.jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: lens
        )
        let second = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/second.jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: lens
        )
        let inserted = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/inserted.jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: lens
        )
        let point = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 10, firstY: 20, secondX: 30, secondY: 40
        )
        var project = PanoProject(images: [first, second], controlPoints: [point])

        let reimportedFirst = SourceImage(
            url: URL(fileURLWithPath: "/Moved/first.jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: lens
        )
        let reimportedSecond = SourceImage(
            url: URL(fileURLWithPath: "/Moved/second.jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: lens
        )

        project.replaceImages([reimportedSecond, inserted, reimportedFirst])

        #expect(project.controlPoints?.first?.firstImage == 2)
        #expect(project.controlPoints?.first?.secondImage == 0)
        #expect(project.controlPoints?.first?.firstX == 10)
        #expect(project.controlPoints?.first?.secondX == 30)
    }

    @Test
    func activeRingIndicesUseVisibleProjectImageNumbers() {
        let images = (0..<3).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 100,
                pixelHeight: 100,
                cameraModel: "Camera",
                lens: LensDescription(
                    model: "Fisheye",
                    focalLengthIn35mm: 16,
                    kind: .fisheye
                ),
                isEnabled: index != 1
            )
        }
        let activeRing = images.filter(\.isEnabled)

        let numbers = HuginOpenCVPanoramaEngine.projectImageNumbers(
            for: [0, 1],
            ringImages: activeRing,
            panoramaImages: images
        )

        #expect(numbers == [1, 3])
    }

    @Test
    func indirectControlPointChainIsAConnectedRingNetwork() {
        let points = [
            DiagnosticControlPoint(
                firstImage: 0, secondImage: 1,
                firstX: 1, firstY: 1, secondX: 1, secondY: 1
            ),
            DiagnosticControlPoint(
                firstImage: 1, secondImage: 2,
                firstX: 1, firstY: 1, secondX: 1, secondY: 1
            ),
            DiagnosticControlPoint(
                firstImage: 2, secondImage: 3,
                firstX: 1, firstY: 1, secondX: 1, secondY: 1
            )
        ]

        let components = HuginOpenCVPanoramaEngine.controlPointComponents(
            imageCount: 4,
            controlPoints: points
        )

        #expect(components == [[0, 1, 2, 3]])
    }

    @Test
    func disconnectedControlPointNetworkReportsActualComponents() {
        let points = [
            DiagnosticControlPoint(
                firstImage: 0, secondImage: 1,
                firstX: 1, firstY: 1, secondX: 1, secondY: 1
            ),
            DiagnosticControlPoint(
                firstImage: 2, secondImage: 3,
                firstX: 1, firstY: 1, secondX: 1, secondY: 1
            )
        ]

        let components = HuginOpenCVPanoramaEngine.controlPointComponents(
            imageCount: 4,
            controlPoints: points
        )

        #expect(components == [[0, 1], [2, 3]])
    }

    @Test @MainActor
    func addingAnyMaskPreservesExistingControlPoints() throws {
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/green-\(index).jpg"),
                captureDate: nil,
                pixelWidth: 100,
                pixelHeight: 100,
                cameraModel: "Camera",
                lens: LensDescription(
                    model: "Fisheye", focalLengthIn35mm: 16, kind: .fisheye
                )
            )
        }
        let point = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 50, firstY: 50, secondX: 50, secondY: 50
        )
        let green = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)], radius: 8,
            erasing: false, protectedArea: true,
            to: nil, width: 100, height: 100
        ))
        let model = AppModel.live(project: PanoProject(
            images: images, controlPoints: [point]
        ))

        model.setSourceMasks(
            red: nil, green: green, for: images[0].id
        )

        #expect(model.editableControlPoints.count == 1)
        #expect(model.project.controlPoints?.count == 1)

        model.sourceMaskIntent = .protect
        model.setMaskData(nil, for: images[0].id)

        #expect(model.editableControlPoints == [point])
        #expect(model.project.controlPoints == [point])

        model.undoMask()

        #expect(model.editableControlPoints == [point])
        #expect(model.project.controlPoints == [point])
    }

    @Test @MainActor
    func paintingSolvedAutomaticRepairKeepsFrozenPanoramaAndPlacement()
        async throws {
        let sourceData = try #require(SourceMaskRasterizer.applyingCircle(
            center: MaskPoint(x: 0.5, y: 0.5),
            radius: 40,
            erasing: false,
            to: nil,
            width: 100,
            height: 100
        ))
        let sourceURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-repair.png"
        )
        try sourceData.write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let repair = SourceImage(
            url: sourceURL,
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: "NIKON D80",
            lens: LensDescription(
                model: "Sigma 8mm",
                focalLengthIn35mm: 12,
                kind: .fisheye
            ),
            role: .automatic,
            automaticRole: .fillOnly,
            automaticDirection: .nadir
        )
        let placement = NadirRepairPlacement(
            imageID: repair.id,
            localHomography: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            matchedFeatureCount: 42,
            localViewFieldOfView: 120
        )
        let model = AppModel.live(
            project: PanoProject(
                images: [repair],
                stitching: StitchingConfiguration(
                    engine: .automatic,
                    projection: .equirectangular,
                    lensProfile: .sigma8DX,
                    inputHorizontalFieldOfView: 165.38
                ),
                nadirRepairPlacement: placement
            ),
            panoramaData: sourceData
        )

        #expect(model.stitchedResultURL != nil)
        model.setSourceMasks(
            red: sourceData, green: nil, for: repair.id
        )

        #expect(model.stitchedResultURL != nil)
        #expect(model.project.nadirRepairPlacement == placement)
        #expect(model.maskDataByImageID[repair.id] == sourceData)
        for _ in 0..<500 where model.phase == .updatingRepair {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test
    func removingImageDropsConnectedPointsAndRemapsRemainingIndices() {
        let images = (0..<4).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 4_000,
                pixelHeight: 6_000,
                cameraModel: "Camera",
                lens: LensDescription(
                    model: "Fisheye",
                    focalLengthIn35mm: 16,
                    kind: .fisheye
                )
            )
        }
        let connected = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 10, firstY: 20, secondX: 30, secondY: 40
        )
        let retained = DiagnosticControlPoint(
            firstImage: 2, secondImage: 3,
            firstX: 50, firstY: 60, secondX: 70, secondY: 80
        )
        var project = PanoProject(
            images: images,
            controlPoints: [connected, retained]
        )

        project.removeImage(at: 1)

        #expect(project.images.map(\.id) == [images[0].id, images[2].id, images[3].id])
        #expect(project.controlPoints?.count == 1)
        #expect(project.controlPoints?.first?.id == retained.id)
        #expect(project.controlPoints?.first?.firstImage == 1)
        #expect(project.controlPoints?.first?.secondImage == 2)
    }

    @Test
    func panoramaSeamIsCenteredBetweenRingImages() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizardTests/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let source = directory.appending(path: "source.pto")
        let destination = directory.appending(path: "destination.pto")
        try """
        i w4000 h6000 f21 v87.44 r0 p0 y7.75 n\"one.tif\"
        i w4000 h6000 f21 v=0 r0 p0 y67.75 n\"two.tif\"
        i w4000 h6000 f21 v=0 r0 p-90 y42 n\"zenith.tif\"
        """.write(to: source, atomically: true, encoding: .utf8)

        try HuginProjectFile.centeringPanoramaSeamBetweenRingImages(
            from: source,
            to: destination,
            ringImageCount: 6
        )

        let orientations = try HuginProjectFile.orientations(in: destination)
        #expect(abs(orientations[0].yaw - -150) < 0.000_001)
        #expect(abs(orientations[1].yaw - -90) < 0.000_001)
        #expect(abs(orientations[2].yaw - -115.75) < 0.000_001)
    }

    @Test
    func nikon105UsesEquisolidHuginProjection() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizardTests/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let source = directory.appending(path: "source.pto")
        let destination = directory.appending(path: "destination.pto")
        let recoveredDestination = directory.appending(
            path: "recovered.pto"
        )
        try """
        # hugin project file
        i w4000 h6000 f3 v87.44 r0 p0 y0 a0 b0 c0 d0 e0 n\"one.tif\"
        i w4000 h6000 f3 v=0 r0 p0 y60 a=0 b=0 c=0 d=0 e=0 n\"two.tif\"
        v
        # control points
        """.write(to: source, atomically: true, encoding: .utf8)

        try HuginProjectFile.configuringNikon105PoseOptimization(
            from: source,
            to: destination,
            horizontalFieldOfView: 87.44,
            poseSeeds: [
                PanoramaOrientation(yaw: 0, pitch: 0, roll: 0),
                PanoramaOrientation(yaw: 60, pitch: 0, roll: 0)
            ]
        )

        let imageLines = try HuginProjectFile.imageLines(in: destination)
        #expect(imageLines.count == 2)
        #expect(imageLines.allSatisfy { $0.contains(" f21 ") })

        try HuginProjectFile.configuringNikon105PoseOptimization(
            from: source,
            to: recoveredDestination,
            horizontalFieldOfView: 87.44,
            poseSeeds: [
                PanoramaOrientation(yaw: 2, pitch: -51, roll: 3),
                PanoramaOrientation(yaw: 91, pitch: 4, roll: -2)
            ]
        )
        let recovered = try HuginProjectFile.orientations(
            in: recoveredDestination
        )
        #expect(recovered[0] == PanoramaOrientation(
            yaw: 2, pitch: -51, roll: 3
        ))
        #expect(recovered[1] == PanoramaOrientation(
            yaw: 91, pitch: 4, roll: -2
        ))
    }

    @Test
    func sigmaLensRefinementOptimizesOpticalCenter() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizardTests/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let source = directory.appending(path: "source.pto")
        let destination = directory.appending(path: "destination.pto")
        try """
        # hugin project file
        i w2600 h3888 f21 v165.38 r0 p0 y0 a0 b0 c0 d0 e0 n"one.tif"
        i w2600 h3888 f21 v=0 r0 p0 y90 a=0 b=0 c=0 d=0 e=0 n"two.tif"
        v
        # control points
        """.write(to: source, atomically: true, encoding: .utf8)

        try HuginProjectFile.configuringSigmaLensRefinement(
            from: source,
            to: destination
        )

        let contents = try String(contentsOf: destination, encoding: .utf8)
        #expect(contents.contains("v d0"))
        #expect(contents.contains("v e0"))
    }

    @Test
    func nikon105LensRefinementOptimizesDistortionAndOpticalCenter() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizardTests/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let source = directory.appending(path: "source.pto")
        let destination = directory.appending(path: "destination.pto")
        try """
        # hugin project file
        i w2000 h3008 f21 v87.44 r0 p0 y0 a-0.02 b0.06 c-0.05 d4 e-1 n"one.tif"
        i w2000 h3008 f21 v=0 r0 p0 y45 a=0 b=0 c=0 d=0 e=0 n"two.tif"
        v
        # control points
        """.write(to: source, atomically: true, encoding: .utf8)

        try HuginProjectFile.configuringNikon105LensRefinement(
            from: source,
            to: destination
        )

        let contents = try String(contentsOf: destination, encoding: .utf8)
        for variable in ["a0", "b0", "c0", "d0", "e0"] {
            #expect(contents.contains("v \(variable)"))
        }
    }

    @Test
    func sigmaFisheyeFactorPointMappingRoundTrips() {
        let mapped = HuginOpenCVPanoramaEngine.remappingFisheyePoint(
            x: 900, y: 700, width: 2_600, height: 3_888,
            sourceFactor: -0.526971, destinationFactor: -0.5
        )
        let restored = HuginOpenCVPanoramaEngine.remappingFisheyePoint(
            x: mapped.0, y: mapped.1, width: 2_600, height: 3_888,
            sourceFactor: -0.5, destinationFactor: -0.526971
        )
        #expect(abs(restored.0 - 900) < 0.000_001)
        #expect(abs(restored.1 - 700) < 0.000_001)
    }

    @Test @MainActor
    func sourceSelectionUsesShiftClickForRightControlPointImage() {
        let images = (0..<3).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/panorama/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 4_000,
                pixelHeight: 6_000,
                cameraModel: "Camera",
                lens: LensDescription(
                    model: "Fisheye",
                    focalLengthIn35mm: 16,
                    kind: .fisheye
                )
            )
        }
        let model = AppModel.live(project: PanoProject(images: images))

        model.selectSourceImage(images[1].id, asRightImage: false)
        #expect(model.selection == .source(images[1].id))
        #expect(model.mainSourceImageID == images[1].id)
        #expect(model.rightSourceImageID == nil)

        model.selectSourceImage(images[2].id, asRightImage: true)
        #expect(model.selection == .controlPoints)
        #expect(model.mainSourceImageID == images[1].id)
        #expect(model.rightSourceImageID == images[2].id)

        model.selectSourceImage(images[0].id, asRightImage: true)
        #expect(model.mainSourceImageID == images[1].id)
        #expect(model.rightSourceImageID == images[0].id)

        model.selectSourceImage(images[2].id, asRightImage: false)
        #expect(model.selection == .source(images[2].id))
        #expect(model.mainSourceImageID == images[2].id)
        #expect(model.rightSourceImageID == nil)
    }

    @Test @MainActor
    func allAlignmentImagesCanShareControlPointsRegardlessOfDirection() {
        let lens = LensDescription(
            model: "Fisheye",
            focalLengthIn35mm: 16,
            kind: .fisheye
        )
        let directions: [SourceImage.Direction] = [
            .horizontal, .horizontal, .nadir, .zenith
        ]
        let images = directions.enumerated().map { index, direction in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/panorama/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 4_000,
                pixelHeight: 6_000,
                cameraModel: "Camera",
                lens: lens,
                direction: direction,
                role: .alignment
            )
        }
        let model = AppModel.live(project: PanoProject(images: images))

        #expect(model.canStitch)

        model.selectSourceImage(images[1].id, asRightImage: false)
        model.selectSourceImage(images[2].id, asRightImage: true)
        #expect(model.selection == .controlPoints)
        #expect(model.mainSourceImageID == images[1].id)
        #expect(model.rightSourceImageID == images[2].id)

        model.selectSourceImage(images[1].id, asRightImage: false)
        model.selectSourceImage(images[3].id, asRightImage: true)
        #expect(model.selection == .controlPoints)
        #expect(model.mainSourceImageID == images[1].id)
        #expect(model.rightSourceImageID == images[3].id)

        model.selectSourceImage(images[2].id, asRightImage: false)
        model.selectSourceImage(images[3].id, asRightImage: true)
        #expect(model.selection == .controlPoints)
        #expect(model.mainSourceImageID == images[2].id)
        #expect(model.rightSourceImageID == images[3].id)

        let pointID = model.addPredictedControlPoint(
            to: ControlPointPair.ID(firstImage: 1, secondImage: 3),
            point: CGPoint(x: 120, y: 240),
            in: 1
        )
        #expect(model.project.controlPoints?.contains { point in
            point.id == pointID && point.pair == ControlPointPair.ID(
                firstImage: 1, secondImage: 3
            )
        } == true)
    }

    @Test @MainActor
    func fillOnlyRepairsCanShareControlPointsWithHorizontalImages() {
        let lens = LensDescription(
            model: "Fisheye",
            focalLengthIn35mm: 16,
            kind: .fisheye
        )
        let images = (0..<8).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/DSC_\(index).JPG"),
                captureDate: nil,
                pixelWidth: 6_000,
                pixelHeight: 4_000,
                cameraModel: "Camera",
                lens: lens,
                direction: index == 6 ? .nadir : (index == 7 ? .zenith : .horizontal),
                role: index >= 6 ? .fillOnly : .alignment
            )
        }
        let model = AppModel.live(project: PanoProject(images: images))

        model.selectSourceImage(images[4].id, asRightImage: false)
        model.selectSourceImage(images[6].id, asRightImage: true)

        #expect(model.selection == .controlPoints)
        #expect(model.mainSourceImageID == images[4].id)
        #expect(model.rightSourceImageID == images[6].id)
    }

    @Test @MainActor
    func projectKeepsControlPointsFromRingToFillOnlyPoleImages() {
        let lens = LensDescription(
            model: "Fisheye", focalLengthIn35mm: 16, kind: .fisheye
        )
        let images = (0..<4).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).jpg"),
                captureDate: nil,
                pixelWidth: index == 3 ? 6_000 : 4_000,
                pixelHeight: index == 3 ? 4_000 : 6_000,
                cameraModel: "Camera",
                lens: lens,
                direction: index == 3 ? .nadir : .horizontal,
                role: index == 3 ? .fillOnly : .alignment
            )
        }
        let ringPoint = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 10, firstY: 20, secondX: 30, secondY: 40
        )
        let polePoint = DiagnosticControlPoint(
            firstImage: 1, secondImage: 3,
            firstX: 10, firstY: 20, secondX: 30, secondY: 40
        )
        let model = AppModel.live(project: PanoProject(
            images: images,
            controlPoints: [ringPoint, polePoint]
        ))

        #expect(model.project.controlPoints == [ringPoint, polePoint])
        #expect(model.editableControlPoints == [ringPoint, polePoint])
    }

    @Test @MainActor
    func invisiblePredictedCounterpartFallsBackToImageCenter() {
        let lens = LensDescription(
            model: "Fisheye",
            focalLengthIn35mm: 16,
            kind: .fisheye
        )
        let images = [
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/large.jpg"),
                captureDate: nil,
                pixelWidth: 1_000,
                pixelHeight: 1_000,
                cameraModel: nil,
                lens: lens
            ),
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/small.jpg"),
                captureDate: nil,
                pixelWidth: 100,
                pixelHeight: 80,
                cameraModel: nil,
                lens: lens
            )
        ]
        let model = AppModel.live(project: PanoProject(images: images))
        let id = model.addPredictedControlPoint(
            to: ControlPointPair.ID(firstImage: 0, secondImage: 1),
            point: CGPoint(x: 900, y: 900),
            in: 0
        )
        let point = model.editableControlPoints.first { $0.id == id }

        #expect(point?.secondX == 50)
        #expect(point?.secondY == 40)
    }

    @Test @MainActor
    func missingProjectionFallsBackToImageCenter() {
        let lens = LensDescription(
            model: "Fisheye",
            focalLengthIn35mm: 16,
            kind: .fisheye
        )
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 1_000,
                pixelHeight: 800,
                cameraModel: nil,
                lens: lens
            )
        }
        let model = AppModel.live(project: PanoProject(images: images))

        let id = model.addPredictedControlPoint(
            to: ControlPointPair.ID(firstImage: 0, secondImage: 1),
            point: CGPoint(x: 100, y: 120),
            in: 0
        )
        let point = model.editableControlPoints.first { $0.id == id }

        #expect(point?.secondX == 500)
        #expect(point?.secondY == 400)
    }

    @Test
    func controlPointCoordinatesFollowExifDisplayOrientation() {
        #expect(
            ControlPointCoordinateSpace.orientedSize(
                rawWidth: 6_000,
                rawHeight: 4_000,
                displayedWidth: 2_000,
                displayedHeight: 3_000
            ) == CGSize(width: 4_000, height: 6_000)
        )
        #expect(
            ControlPointCoordinateSpace.orientedSize(
                rawWidth: 6_000,
                rawHeight: 4_000,
                displayedWidth: 3_000,
                displayedHeight: 2_000
            ) == CGSize(width: 6_000, height: 4_000)
        )
    }

    @Test @MainActor
    func emptyControlPointsAllowAutomaticRegenerationWhenProjectIsRestored() {
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/panorama/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 2_000,
                pixelHeight: 3_008,
                cameraModel: "Camera",
                lens: LensDescription(
                    model: "Fisheye",
                    focalLengthIn35mm: 16,
                    kind: .fisheye
                )
            )
        }
        let model = AppModel.live(
            project: PanoProject(images: images, controlPoints: [])
        )

        #expect(model.project.controlPoints == nil)
        #expect(model.editableControlPoints.isEmpty)
        #expect(model.controlPointEditorDiagnostics?.cleanedPoints == [])
        #expect(model.canStitch)
    }

    @Test @MainActor
    func createPanoramaPreservesEditedControlPointsAndUsesCurrentMasks() async {
        let lens = LensDescription(
            model: "Sigma 8mm",
            focalLengthIn35mm: 8,
            kind: .fisheye
        )
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/panorama/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 2_000,
                pixelHeight: 3_008,
                cameraModel: "Camera",
                lens: lens
            )
        }
        let editedPoint = DiagnosticControlPoint(
            firstImage: 0,
            secondImage: 1,
            firstX: 123,
            firstY: 456,
            secondX: 789,
            secondY: 321
        )
        let panoramaMask = Data([1])
        let protectedMask = Data([2])
        let engine = RecordingPanoramaEngine()
        let model = AppModel(
            project: PanoProject(
                images: images,
                controlPoints: [editedPoint]
            ),
            importer: ImageImportService(metadataReader: ImageMetadataReader()),
            grouper: PanoramaGroupingService(),
            panoramaEngine: engine,
            exporter: FilePanoramaExporter(),
            masks: [images[0].id: panoramaMask],
            protectedMasks: [images[1].id: protectedMask]
        )

        model.stitch()

        for _ in 0..<100 where await engine.stitchCallCount == 0 {
            await Task.yield()
        }

        #expect(await engine.receivedControlPoints == [editedPoint])
        #expect(await engine.receivedControlPointsAreAuthoritative)
        #expect(await engine.receivedMasks == [images[0].id: panoramaMask])
        #expect(
            await engine.receivedProtectedMasks
                == [images[1].id: protectedMask]
        )
    }

    @Test @MainActor
    func repeatedPairSuggestionsAddTenWidelySeparatedPointsAtATime() {
        let lens = LensDescription(
            model: "Fisheye",
            focalLengthIn35mm: 16,
            kind: .fisheye
        )
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/grid-\(index).jpg"),
                captureDate: nil,
                pixelWidth: 1_000,
                pixelHeight: 1_000,
                cameraModel: "Camera",
                lens: lens
            )
        }
        let existing = DiagnosticControlPoint(
            firstImage: 0,
            secondImage: 1,
            firstX: 500,
            firstY: 500,
            secondX: 500,
            secondY: 500
        )
        var grid: [DiagnosticControlPoint] = []
        for row in 0..<5 {
            for column in 0..<5 {
                grid.append(DiagnosticControlPoint(
                    firstImage: 0,
                    secondImage: 1,
                    firstX: Double(column * 200),
                    firstY: Double(row * 200),
                    secondX: Double(column * 200),
                    secondY: Double(row * 200)
                ))
            }
        }
        let clustered = DiagnosticControlPoint(
            firstImage: 0,
            secondImage: 1,
            firstX: 505,
            firstY: 505,
            secondX: 505,
            secondY: 505
        )
        let candidates = grid + [clustered]

        let first = AppModel.spatiallyDistributedControlPoints(
            from: candidates,
            existing: [existing],
            images: images,
            maximumCount: AppModel.suggestedControlPointBatchSize
        )
        let second = AppModel.spatiallyDistributedControlPoints(
            from: candidates,
            existing: [existing] + first,
            images: images,
            maximumCount: AppModel.suggestedControlPointBatchSize
        )
        let third = AppModel.spatiallyDistributedControlPoints(
            from: candidates,
            existing: [existing] + first + second,
            images: images,
            maximumCount: AppModel.suggestedControlPointBatchSize
        )
        let selectedIDs = Set<UUID>((first + second + third).map { $0.id })

        #expect(first.count == 10)
        #expect(second.count == 10)
        #expect(third.count == 5)
        #expect(selectedIDs == Set<UUID>(grid.map { $0.id }))
        #expect(!selectedIDs.contains(clustered.id))
    }

    @Test
    func projectRoundTripsThroughJSON() throws {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/one.jpg"),
            captureDate: Date(timeIntervalSince1970: 1_000),
            pixelWidth: 2_000,
            pixelHeight: 3_008,
            cameraModel: "Camera",
            lens: LensDescription(
                model: "Fisheye",
                focalLengthIn35mm: 16,
                kind: .fisheye
            ),
            direction: .nadir,
            role: .fillOnly
        )
        let project = PanoProject(
            title: "Lissabon",
            images: [image],
            stitching: StitchingConfiguration(
                engine: .hugin,
                projection: .equirectangular,
                lensProfile: .nikon105DX,
                inputHorizontalFieldOfView: 100
            ),
            controlPoints: [
                DiagnosticControlPoint(
                    firstImage: 0,
                    secondImage: 1,
                    firstX: 120,
                    firstY: 340,
                    secondX: 560,
                    secondY: 780
                )
            ],
            nadirRepairPlacement: NadirRepairPlacement(
                imageID: image.id,
                localHomography: [
                    1, 0, 12,
                    0, 1, -8,
                    0, 0, 1
                ],
                matchedFeatureCount: 42,
                localViewFieldOfView: 120,
                manualAdjustment: NadirRepairAdjustment(
                    translationX: 18,
                    translationY: -7,
                    rotationDegrees: 1.25,
                    scale: 1.03,
                    cornerOffsets: [
                        -12, 8,
                        18, -5,
                        24, 16,
                        -9, 11
                    ]
                )
            ),
            nadirAIRetouchPrompt: "Behåll stolarna",
            zenithAIRetouchPrompt: "Behåll takkronan",
            previewViewpoint: PanoramaViewpoint(
                yawRadians: 1.25,
                pitchRadians: -0.35,
                verticalFieldOfViewDegrees: 51
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            PanoProject.self,
            from: encoder.encode(project)
        )

        #expect(decoded == project)
    }

    @Test
    func nadirAdjustmentIsStoredWithoutChangingRegistration() throws {
        let imageID = UUID()
        var project = PanoProject(
            nadirRepairPlacement: NadirRepairPlacement(
                imageID: imageID,
                localHomography: [
                    1, 0, 12,
                    0, 1, -8,
                    0, 0, 1
                ],
                matchedFeatureCount: 42,
                localViewFieldOfView: 120
            )
        )
        let originalHomography = try #require(
            project.nadirRepairPlacement?.localHomography
        )
        let adjustment = NadirRepairAdjustment(
            translationX: 23,
            translationY: -11,
            rotationDegrees: 0.8,
            scale: 0.97,
            cornerOffsets: [
                -10, 4,
                12, -6,
                16, 9,
                -7, 13
            ]
        )

        project.setNadirRepairAdjustment(adjustment)

        #expect(project.nadirRepairPlacement?.manualAdjustment == adjustment)
        #expect(
            project.nadirRepairPlacement?.localHomography
                == originalHomography
        )

        project.setNadirRepairAdjustment(.identity)

        #expect(project.nadirRepairPlacement?.manualAdjustment == nil)
        #expect(
            project.nadirRepairPlacement?.localHomography
                == originalHomography
        )
    }

    @Test
    func firstImportNamesUntitledProject() {
        let captureDate = Date(timeIntervalSince1970: 1_000)
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/one.jpg"),
            captureDate: captureDate,
            pixelWidth: 2_000,
            pixelHeight: 3_008,
            cameraModel: nil,
            lens: LensDescription(
                model: nil,
                focalLengthIn35mm: nil,
                kind: .unknown
            )
        )
        var project = PanoProject()

        project.replaceImages([image])

        #expect(project.title == captureDate.formatted(date: .abbreviated, time: .omitted))
    }

    @Test
    func newImagesUseAutomaticPositioningByDefault() {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/one.jpg"),
            captureDate: nil,
            pixelWidth: 2_000,
            pixelHeight: 3_008,
            cameraModel: nil,
            lens: LensDescription(
                model: nil,
                focalLengthIn35mm: nil,
                kind: .unknown
            )
        )

        #expect(image.role == .automatic)
        #expect(image.effectiveRole == .alignment)
    }

    @Test
    func automaticRepairKeepsPointsToThePositioningRig() {
        let lens = LensDescription(
            model: "Fisheye", focalLengthIn35mm: 16, kind: .fisheye
        )
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 2_000,
                pixelHeight: 3_008,
                cameraModel: nil,
                lens: lens
            )
        }
        let point = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 10, firstY: 20, secondX: 30, secondY: 40
        )
        var project = PanoProject(
            images: images,
            controlPoints: [point]
        )

        project.applyAutomaticPositioningDecisions([
            images[0].id: AutomaticPositioningDecision(
                role: .alignment, direction: .horizontal
            ),
            images[1].id: AutomaticPositioningDecision(
                role: .fillOnly, direction: .nadir
            )
        ])

        #expect(project.images[0].effectiveRole == .alignment)
        #expect(project.images[1].effectiveRole == .fillOnly)
        #expect(project.images[1].effectiveDirection == .nadir)
        #expect(project.controlPoints == [point])
    }

    @Test
    func manuallyMarkingRepairKeepsItsControlPointsVisible() {
        let lens = LensDescription(
            model: "Fisheye", focalLengthIn35mm: 16, kind: .fisheye
        )
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/Pictures/\(index).jpg"),
                captureDate: nil,
                pixelWidth: 2_000,
                pixelHeight: 3_008,
                cameraModel: nil,
                lens: lens
            )
        }
        let point = DiagnosticControlPoint(
            firstImage: 0, secondImage: 1,
            firstX: 10, firstY: 20, secondX: 30, secondY: 40
        )
        var project = PanoProject(images: images, controlPoints: [point])

        project.setRole(.fillOnly, for: images[1].id)

        #expect(project.images[1].direction == .horizontal)
        #expect(project.controlPoints == [point])
    }

    @Test
    func assigningRepairAreaSetsRoleAndDirectionAtomically() {
        let zenith = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/zenith.jpg"),
            captureDate: nil,
            pixelWidth: 2_000,
            pixelHeight: 3_008,
            cameraModel: nil,
            lens: LensDescription(
                model: nil,
                focalLengthIn35mm: nil,
                kind: .unknown
            )
        )
        let nadir = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/nadir.jpg"),
            captureDate: nil,
            pixelWidth: 2_000,
            pixelHeight: 3_008,
            cameraModel: nil,
            lens: LensDescription(
                model: nil,
                focalLengthIn35mm: nil,
                kind: .unknown
            )
        )
        var project = PanoProject(images: [zenith, nadir])

        project.setRepairArea(.zenith, for: zenith.id)
        project.setRepairArea(.nadir, for: nadir.id)

        #expect(project.images[0].role == .fillOnly)
        #expect(project.images[0].direction == .zenith)
        #expect(project.images[1].role == .fillOnly)
        #expect(project.images[1].direction == .nadir)
    }

    @Test
    func changingRepairAreaPreservesGlobalRigCache() {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/repair.tif"),
            captureDate: nil,
            pixelWidth: 2_592,
            pixelHeight: 3_872,
            cameraModel: nil,
            lens: LensDescription(
                model: "Sigma 8mm",
                focalLengthIn35mm: 12,
                kind: .fisheye
            ),
            direction: .nadir,
            role: .fillOnly
        )
        var project = PanoProject(
            images: [image],
            cachedRigImageLines: ["ring": "i cached"],
            cachedRigSignature: "old",
            nadirRepairPlacement: NadirRepairPlacement(
                imageID: image.id,
                localHomography: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                matchedFeatureCount: 20,
                localViewFieldOfView: 120
            )
        )

        project.setRepairArea(.zenith, for: image.id)

        #expect(project.cachedRigImageLines == ["ring": "i cached"])
        #expect(project.cachedRigSignature == "old")
        #expect(project.images[0].role == .fillOnly)
        #expect(project.images[0].direction == .zenith)
        #expect(project.nadirRepairPlacement == nil)
        #expect(project.zenithRepairPlacement == nil)
    }
}

private actor RecordingPanoramaEngine: PanoramaEngine {
    private(set) var stitchCallCount = 0
    private(set) var receivedControlPoints: [DiagnosticControlPoint]?
    private(set) var receivedControlPointsAreAuthoritative = false
    private(set) var receivedMasks: [UUID: Data] = [:]
    private(set) var receivedProtectedMasks: [UUID: Data] = [:]

    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        controlPoints: [DiagnosticControlPoint]?,
        controlPointsAreAuthoritative: Bool,
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult {
        stitchCallCount += 1
        receivedControlPoints = controlPoints
        receivedControlPointsAreAuthoritative = controlPointsAreAuthoritative
        receivedMasks = masks
        receivedProtectedMasks = protectedMasks
        return PanoramaStitchResult(
            url: URL(fileURLWithPath: "/tmp/recorded-panorama.jpg"),
            rigImageLines: [:],
            nadirRepair: nil,
            zenithRepair: nil,
            controlPointDiagnostics: nil
        )
    }

    func optimizeControlPoints(
        _ panorama: PanoramaSet,
        controlPoints: [DiagnosticControlPoint],
        controlPointsAreAuthoritative: Bool,
        configuration: StitchingConfiguration
    ) async throws -> ControlPointOptimizationResult {
        ControlPointOptimizationResult(diagnostics: ControlPointDiagnostics(
            images: panorama.images,
            rawPoints: controlPoints,
            cleanedPoints: controlPoints
        ))
    }
}
