import Foundation
import Testing
@testable import PanoWizard

struct PublishThumbnailRendererTests {
    @Test("Thumbnail renders the exported camera, perspective FOV and adjustments at 640x360")
    @MainActor
    func actualViewer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("publish-thumbnail-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.png")
        var input = RGBAImage(width: 512, height: 256)
        for y in 0..<256 { for x in 0..<512 {
            input.setPixel(Pixel(r: Double(x) / 511, g: Double(y) / 255, b: 0.25, a: 1), x: x, y: y)
        } }
        try input.writePNG(to: source)
        for fov in [60.0, 90.0] {
            let html = directory.appendingPathComponent("view-\(Int(fov)).html")
            let jpg = html.deletingPathExtension().appendingPathExtension("jpg")
            try await FilePanoramaExporter().exportHTML(panoramaURL: source, adjustments: .neutral,
                title: "Thumbnail test", initialViewpoint: PanoramaViewpoint(yawRadians: .pi / 2,
                pitchRadians: 0, verticalFieldOfViewDegrees: fov), size: .original, jpegQuality: 1, to: html)
            try await PublishThumbnailRenderer.render(htmlURL: html, to: jpg)
            let image = try RGBAImage(contentsOf: jpg)
            #expect(image.width == 640 && image.height == 360)
            for x in [160, 320, 480] {
                let expected = 0.75 + atan((Double(x) * 2 / 640 - 1) * (16.0 / 9) * tan(fov * .pi / 360)) / (2 * .pi)
                #expect(abs(image.pixel(x: x, y: 180).r - expected) < 0.035)
            }
        }
        print("THUMBNAIL_FIXTURE=\(directory.path)")
    }
}

struct PublishThumbnailLiveTests {
    @Test("Publish HTML with an atomic companion JPEG to the configured gallery",
          .enabled(if: ProcessInfo.processInfo.environment["PANOWIZARD_PUBLISH_LIVE_TEST"] == "1"))
    @MainActor
    func publishPair() async throws {
        let connection = SFTPConnection.load()
        guard ["panorama.egelberg.se", "server.egelberg.se"].contains(URL(string: connection.publicBaseURL)?.host ?? ""),
              connection.remoteDirectory.hasSuffix("/panorama"), let trusted = connection.hostKey else {
            throw PublishError.message("Live test requires the existing trusted Panorama Browser connection.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("publish-live-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.png")
        var image = RGBAImage(width: 512, height: 256)
        for y in 0..<256 { for x in 0..<512 {
            image.setPixel(Pixel(r: Double(x)/511, g: Double(y)/255, b: 0.3, a: 1), x: x, y: y)
        } }
        try image.writePNG(to: source)
        let html = directory.appendingPathComponent("panorama.html")
        let jpg = directory.appendingPathComponent("panorama.jpg")
        try await FilePanoramaExporter().exportHTML(panoramaURL: source, adjustments: .neutral,
            title: "Publish thumbnail test", initialViewpoint: PanoramaViewpoint(yawRadians: 0.8,
            pitchRadians: 0.2, verticalFieldOfViewDegrees: 60), size: .original, jpegQuality: 1, to: html)
        let verify: @Sendable (String) async throws -> Void = { key in
            guard key == trusted else { throw PublishError.message("Unexpected live server host key") }
        }
        let token = UUID().uuidString
        let with = "zz-publish-test-\(token)-åäö.html"
        try await PublishThumbnailRenderer.render(htmlURL: html, to: jpg)
        try await SFTPPublisher.upload(localURL: html, connection: connection, filename: with,
            subdirectory: "2008", verifyHost: verify, confirmOverwrite: { false })
        try await SFTPPublisher.upload(localURL: jpg, connection: connection, filename: with,
            subdirectory: "2008", thumbnail: true, verifyHost: verify, confirmOverwrite: { false })
        do {
            try await SFTPPublisher.upload(localURL: jpg, connection: connection, filename: with,
                subdirectory: "2008", thumbnail: true, verifyHost: verify, confirmOverwrite: { false })
            Issue.record("JPEG overwritten without approval")
        } catch is CancellationError { }
        try await SFTPPublisher.upload(localURL: jpg, connection: connection, filename: with,
            subdirectory: "2008", thumbnail: true, verifyHost: verify, confirmOverwrite: { true })
        do {
            try await SFTPPublisher.upload(localURL: directory.appendingPathComponent("missing.jpg"),
                connection: connection, filename: with, subdirectory: "2008", thumbnail: true,
                verifyHost: verify, confirmOverwrite: { true })
            Issue.record("Missing local JPEG reported success")
        } catch { #expect(error.localizedDescription.contains("SFTP upload failed")) }
        print("PUBLISH_LIVE_FILE=\(with)")
    }
}
