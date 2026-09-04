import AppKit
import Foundation
import ImageIO
import OpenCVBridge
import Testing
@testable import PanoWizard

@Suite("Trial panorama engine")
struct TrialPanoramaEngineTests {
    @Test("Explicit project fixture produces a full panorama")
    func panoramaFixture() async throws {
        guard let projectPath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_TRIAL_PROJECT"
        ] else { return }
        let document = try PanoProjectDocument(
            contentsOf: URL(fileURLWithPath: projectPath)
        )
        let result = try await TrialOpenCVPanoramaEngine().stitch(
            document.project.panorama,
            masks: document.masks,
            protectedMasks: document.protectedMasks
        ) { fraction, stage in
            print("Trial fixture \(Int(fraction * 100))%: \(stage)")
        }
        let image = CGImageSourceCreateWithURL(result.url as CFURL, nil).flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        }
        #expect(image?.width == TrialOpenCVPanoramaEngine.outputWidth)
        #expect(image?.height == TrialOpenCVPanoramaEngine.outputWidth / 2)
        // The two saved exclusion masks intentionally remove part of the
        // nadir. The engine must report that missing source coverage instead
        // of synthesizing replacement pixels.
        #expect(result.coveragePercent > 95)
        print(
            "Trial fixture result: \(result.url.path), "
                + "coverage=\(result.coveragePercent), holes=\(result.holeCount), "
                + "cache=\(result.usedAlignmentCache)"
        )
    }

    @Test("Uses every enabled source and no disabled source")
    func sourceSelection() {
        let first = image(enabled: true)
        let second = image(enabled: false)
        let third = image(enabled: true)

        let selected = TrialOpenCVPanoramaEngine.sourceImages(
            in: PanoramaSet(images: [first, second, third])
        )

        #expect(selected.map(\.id) == [first.id, third.id])
    }

    @Test("App dispatches masks directly to its sole engine")
    @MainActor
    func appDispatch() async throws {
        let first = image(enabled: true)
        let second = image(enabled: true)
        let engine = RecordingEngine()
        let red = Data([1, 2, 3])
        let green = Data([4, 5, 6])
        let model = AppModel(
            project: PanoProject(images: [first, second]),
            importer: ImageImportService(metadataReader: ImageMetadataReader()),
            grouper: PanoramaGroupingService(),
            panoramaEngine: engine,
            exporter: FilePanoramaExporter(),
            masks: [first.id: red],
            protectedMasks: [second.id: green]
        )

        model.stitch()
        for _ in 0..<200 where await engine.callCount == 0 {
            await Task.yield()
        }

        #expect(await engine.callCount == 1)
        #expect(await engine.receivedMasks[first.id] == red)
        #expect(await engine.receivedProtectedMasks[second.id] == green)
    }

    @Test("Native bridge rejects an invalid source set")
    func bridgeValidation() {
        var report = PWTrialStitchReport()
        var error: UnsafeMutablePointer<CChar>?
        let succeeded = PWStitchTrialPanorama(
            nil, nil, nil, 0, nil, nil, 4096, nil, nil, nil, &report, &error
        )
        defer { PWFreeString(error) }
        #expect(succeeded == 0)
        #expect(error != nil)
    }

    @Test("Native bridge creates a 2:1 image and reuses alignment cache")
    func bridgeSmokeTest() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Trial-Test-\(UUID())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.jpg")
        try writeTexturedImage(to: source)
        let output = directory.appending(path: "result.jpg")
        let cache = directory.appending(path: "alignment.yml")
        let allocation = strdup(source.path(percentEncoded: false))
        defer { free(allocation) }
        let paths: [UnsafePointer<CChar>?] = [
            allocation.map { UnsafePointer($0) },
            allocation.map { UnsafePointer($0) }
        ]

        var firstReport = PWTrialStitchReport()
        var firstError: UnsafeMutablePointer<CChar>?
        let firstSucceeded = paths.withUnsafeBufferPointer { buffer in
            PWStitchTrialPanorama(
                buffer.baseAddress,
                nil,
                nil,
                2,
                cache.path(percentEncoded: false),
                output.path(percentEncoded: false),
                512,
                nil,
                nil,
                nil,
                &firstReport,
                &firstError
            )
        }
        defer { PWFreeString(firstError) }
        #expect(
            firstSucceeded == 1,
            Comment(rawValue: firstError.map { String(cString: $0) } ?? "")
        )
        let result = CGImageSourceCreateWithURL(output as CFURL, nil).flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        }
        #expect(result?.width == 512)
        #expect(result?.height == 256)
        let bitmap = try #require(NSBitmapImageRep(
            data: Data(contentsOf: output)
        ))
        var channelDifference = 0.0
        var brightness = 0.0
        var sampleCount = 0.0
        for y in stride(from: 16, to: bitmap.pixelsHigh, by: 32) {
            for x in stride(from: 16, to: bitmap.pixelsWide, by: 32) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let red = Double(color.redComponent)
                let green = Double(color.greenComponent)
                let blue = Double(color.blueComponent)
                channelDifference += max(red, max(green, blue))
                    - min(red, min(green, blue))
                brightness += (red + green + blue) / 3
                sampleCount += 1
            }
        }
        #expect(sampleCount > 0)
        #expect(channelDifference / sampleCount < 0.04)
        #expect(brightness / sampleCount > 0.08)

        var cachedReport = PWTrialStitchReport()
        var cachedError: UnsafeMutablePointer<CChar>?
        let cachedSucceeded = paths.withUnsafeBufferPointer { buffer in
            PWStitchTrialPanorama(
                buffer.baseAddress,
                nil,
                nil,
                2,
                cache.path(percentEncoded: false),
                output.path(percentEncoded: false),
                512,
                nil,
                nil,
                nil,
                &cachedReport,
                &cachedError
            )
        }
        defer { PWFreeString(cachedError) }
        #expect(cachedSucceeded == 1)
        #expect(cachedReport.usedAlignmentCache == 1)
    }

    private func image(enabled: Bool) -> SourceImage {
        SourceImage(
            url: URL(fileURLWithPath: "/tmp/\(UUID()).jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: LensDescription(
                model: nil,
                focalLengthIn35mm: nil,
                kind: .fisheye
            ),
            isEnabled: enabled
        )
    }

    private func writeTexturedImage(to url: URL) throws {
        let size = 512
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * 4,
            bitsPerPixel: 32
        ))
        let pixels = try #require(bitmap.bitmapData)
        var state: UInt32 = 0x6d2b79f5
        for index in 0..<(size * size) {
            state = state &* 1_664_525 &+ 1_013_904_223
            let value = UInt8(truncatingIfNeeded: state >> 16)
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = 255
        }
        let data = try #require(bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.95]
        ))
        try data.write(to: url)
    }
}

private actor RecordingEngine: PanoramaEngine {
    var callCount = 0
    var receivedMasks: [UUID: Data] = [:]
    var receivedProtectedMasks: [UUID: Data] = [:]

    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> PanoramaStitchResult {
        callCount += 1
        receivedMasks = masks
        receivedProtectedMasks = protectedMasks
        progress(1, "Klar")
        return PanoramaStitchResult(
            url: URL(fileURLWithPath: "/tmp/result.jpg"),
            coveragePercent: 100,
            holeCount: 0,
            usedAlignmentCache: false
        )
    }
}
