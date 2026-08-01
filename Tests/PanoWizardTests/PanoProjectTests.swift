import Foundation
import Testing
@testable import PanoWizard

struct PanoProjectTests {
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
            nominalYaws: [0, 60],
            horizontalFieldOfView: 87.44
        )

        let imageLines = try HuginProjectFile.imageLines(in: destination)
        #expect(imageLines.count == 2)
        #expect(imageLines.allSatisfy { $0.contains(" f21 ") })
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

    @Test
    func detectsBroadlyCatastrophicControlPointSet() {
        var project = PanoProject()
        project.controlPoints = (0..<20).map { index in
            DiagnosticControlPoint(
                firstImage: 0,
                secondImage: 1,
                firstX: Double(index),
                firstY: 0,
                secondX: Double(index),
                secondY: 0,
                error: index < 2 ? 4 : 120
            )
        }
        #expect(project.hasCatastrophicControlPointErrors)

        project.controlPoints = project.controlPoints?.enumerated().map {
            index, point in
            var point = point
            point.error = index == 0 ? 120 : 4
            return point
        }
        #expect(!project.hasCatastrophicControlPointErrors)
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

        #expect(model.project.controlPoints == [])
        #expect(model.editableControlPoints.isEmpty)
        #expect(model.controlPointEditorDiagnostics?.cleanedPoints == [])
        #expect(model.canStitch)
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
    func changingImageDirectionInvalidatesRigCache() {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/Pictures/panorama/zenith.tif"),
            captureDate: nil,
            pixelWidth: 2_592,
            pixelHeight: 3_872,
            cameraModel: nil,
            lens: LensDescription(
                model: "Sigma 8mm",
                focalLengthIn35mm: 12,
                kind: .fisheye
            )
        )
        var project = PanoProject(
            images: [image],
            cachedRigImageLines: [image.id.uuidString: "i cached"],
            cachedRigSignature: "old",
            nadirRepairPlacement: NadirRepairPlacement(
                imageID: image.id,
                localHomography: [
                    1, 0, 0,
                    0, 1, 0,
                    0, 0, 1
                ],
                matchedFeatureCount: 20,
                localViewFieldOfView: 120
            )
        )

        project.setDirection(.zenith, for: image.id)

        #expect(project.cachedRigImageLines == nil)
        #expect(project.cachedRigSignature == nil)
        #expect(project.nadirRepairPlacement == nil)
    }
}
