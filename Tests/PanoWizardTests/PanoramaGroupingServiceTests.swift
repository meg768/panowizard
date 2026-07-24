import Foundation
import Testing
@testable import PanoWizard

struct PanoramaGroupingServiceTests {
    private let lens = LensDescription(
        model: "24mm F2.8",
        focalLengthIn35mm: 24,
        kind: .rectilinear
    )

    @Test
    func sortsImagesByCaptureDate() {
        let base = Date(timeIntervalSince1970: 1_000)
        let images = [
            image("third.jpg", date: base.addingTimeInterval(20)),
            image("first.jpg", date: base),
            image("second.jpg", date: base.addingTimeInterval(10))
        ]

        let result = PanoramaGroupingService().group(images)

        #expect(result.count == 1)
        #expect(result[0].images.map(\.filename) == ["first.jpg", "second.jpg", "third.jpg"])
    }

    @Test
    func separatesSetsAfterTimeGap() {
        let base = Date(timeIntervalSince1970: 1_000)
        let images = [
            image("one.jpg", date: base),
            image("two.jpg", date: base.addingTimeInterval(30)),
            image("three.jpg", date: base.addingTimeInterval(300))
        ]

        let result = PanoramaGroupingService(maximumGap: 120).group(images)

        #expect(result.map(\.images.count) == [2, 1])
    }

    @Test
    func separatesDifferentCameras() {
        let base = Date(timeIntervalSince1970: 1_000)
        let images = [
            image("one.jpg", date: base, camera: "Camera A"),
            image("two.jpg", date: base.addingTimeInterval(10), camera: "Camera B")
        ]

        let result = PanoramaGroupingService().group(images)

        #expect(result.count == 2)
    }

    private func image(
        _ filename: String,
        date: Date?,
        camera: String = "Camera"
    ) -> SourceImage {
        SourceImage(
            url: URL(fileURLWithPath: "/tmp/\(filename)"),
            captureDate: date,
            pixelWidth: 4_000,
            pixelHeight: 3_000,
            cameraModel: camera,
            lens: lens
        )
    }
}
