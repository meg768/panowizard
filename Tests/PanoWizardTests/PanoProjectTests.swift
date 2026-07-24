import Foundation
import Testing
@testable import PanoWizard

struct PanoProjectTests {
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
            cachedRigSignature: "old"
        )

        project.setDirection(.zenith, for: image.id)

        #expect(project.cachedRigImageLines == nil)
        #expect(project.cachedRigSignature == nil)
    }
}
