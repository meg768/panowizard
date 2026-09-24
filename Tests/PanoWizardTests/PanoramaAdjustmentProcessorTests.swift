import Foundation
import Testing
@testable import PanoWizard

@Suite("Panorama adjustments")
struct PanoramaAdjustmentProcessorTests {
    @Test("Neutral adjustments preserve the pixel")
    func neutralPreservesPixel() {
        let input = Pixel(r: 0.18, g: 0.42, b: 0.73, a: 0.65)

        let output = adjusted(input, settings: .neutral)

        #expect(abs(output.r - input.r) < 0.000_001)
        #expect(abs(output.g - input.g) < 0.000_001)
        #expect(abs(output.b - input.b) < 0.000_001)
        #expect(output.a == input.a)
    }

    @Test("Exposure brightens all color channels")
    func exposureBrightensPixel() {
        let input = Pixel(r: 0.25, g: 0.35, b: 0.45, a: 1)

        let output = adjusted(
            input,
            settings: PanoramaAdjustments(exposure: 1)
        )

        #expect(output.r > input.r)
        #expect(output.g > input.g)
        #expect(output.b > input.b)
    }

    @Test("Minimum saturation produces grayscale")
    func minimumSaturationProducesGrayscale() {
        let output = adjusted(
            Pixel(r: 0.9, g: 0.35, b: 0.1, a: 1),
            settings: PanoramaAdjustments(saturation: -100)
        )

        #expect(abs(output.r - output.g) < 0.000_001)
        #expect(abs(output.g - output.b) < 0.000_001)
    }

    @Test("Values are constrained to the supported ranges")
    func sanitizesValues() {
        let sanitized = PanoramaAdjustments(
            exposure: 10,
            brightness: -140,
            contrast: 125,
            saturation: -130
        ).sanitized

        #expect(sanitized.exposure == 3)
        #expect(sanitized.brightness == -100)
        #expect(sanitized.contrast == 100)
        #expect(sanitized.saturation == -100)
    }

    @Test("Interactive HTML embeds adjustment values")
    func htmlEmbedsAdjustmentValues() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Adjustment-HTML-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let panoramaURL = directory.appending(path: "panorama.jpg")
        let htmlURL = directory.appending(path: "panorama.html")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: panoramaURL)

        try await FilePanoramaExporter().exportHTML(
            panoramaURL: panoramaURL,
            nadirOverlayURL: nil,
            zenithOverlayURL: nil,
            nadirRetouchURL: nil,
            zenithRetouchURL: nil,
            adjustments: PanoramaAdjustments(
                exposure: 1.25,
                brightness: -17
            ),
            title: "Adjustment Test",
            initialViewpoint: PanoramaViewpoint(),
            to: htmlURL
        )

        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        #expect(html.contains("program,\"exposure\"),1.25"))
        #expect(html.contains("program,\"brightness\"),-17.0"))
        #expect(!html.contains("vignette"))
        #expect(!html.contains("adjustments.exposure"))
    }

    private func adjusted(
        _ pixel: Pixel,
        settings: PanoramaAdjustments
    ) -> Pixel {
        PanoramaAdjustmentProcessor.adjusted(
            pixel,
            settings: settings
        )
    }
}
