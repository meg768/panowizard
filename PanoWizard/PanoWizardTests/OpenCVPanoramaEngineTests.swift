import AppKit
import Foundation
import ImageIO
import OpenCVBridge
import Testing
@testable import PanoWizard

@Suite("OpenCV panorama engine")
struct OpenCVPanoramaEngineTests {
    @Test("Explicit project fixture produces a full panorama")
    func panoramaFixture() async throws {
        guard let projectPath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_PANORAMA_PROJECT"
        ] else { return }
        let document = try PanoProjectDocument(
            contentsOf: URL(fileURLWithPath: projectPath)
        )
        let result = try await OpenCVPanoramaEngine().stitch(
            document.project.panorama,
            masks: document.masks,
            protectedMasks: document.protectedMasks
        ) { fraction, stage in
            print("Panorama fixture \(Int(fraction * 100))%: \(stage)")
        }
        let image = CGImageSourceCreateWithURL(result.url as CFURL, nil).flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        }
        #expect((image?.width ?? 0) >= 512)
        #expect(image?.height == (image?.width ?? 0) / 2)
        #expect(result.ringImageCount == 6)
        #expect(result.usedSupplementalImageCount == 2)
        #expect(result.warningMessage == nil)
        #expect(result.coveragePercent > 95)
        print(
            "Panorama fixture result: \(result.url.path), "
                + "coverage=\(result.coveragePercent), holes=\(result.holeCount), "
                + "cache=\(result.usedAlignmentCache)"
        )
    }

    @Test("Uses every enabled source and no disabled source")
    func sourceSelection() {
        let first = image(enabled: true)
        let second = image(enabled: false)
        let third = image(enabled: true)

        let selected = OpenCVPanoramaEngine.sourceImages(
            in: PanoramaSet(images: [first, second, third])
        )

        #expect(selected.map(\.id) == [first.id, third.id])
    }

    @Test("Source roles and rotation change the alignment cache identity")
    func sourceStateChangesCacheIdentity() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Cache-Test-\(UUID()).jpg"
        )
        try Data([1, 2, 3]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        var source = image(enabled: true)
        source.url = sourceURL
        let original = try OpenCVPanoramaEngine.alignmentCacheURL(
            images: [source],
            masks: [:]
        )
        source.rotation = .left90
        let rotated = try OpenCVPanoramaEngine.alignmentCacheURL(
            images: [source],
            masks: [:]
        )
        source.rotation = .none
        source.role = .fillOnly
        let supplemental = try OpenCVPanoramaEngine.alignmentCacheURL(
            images: [source],
            masks: [:]
        )

        #expect(original != rotated)
        #expect(original != supplemental)
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
        var report = PWStitchReport()
        var error: UnsafeMutablePointer<CChar>?
        let succeeded = PWStitchPanorama(
            nil, nil, nil, 0, nil, nil, 4096, nil, nil, nil, &report, &error
        )
        defer { PWFreeString(error) }
        #expect(succeeded == 0)
        #expect(error != nil)
    }

    @Test("Native bridge creates a 2:1 image and reuses alignment cache")
    func bridgeSmokeTest() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Engine-Test-\(UUID())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.jpg")
        try writeTexturedImage(to: source)
        let output = directory.appending(path: "result.png")
        let cache = directory.appending(path: "alignment.yml")
        let allocation = strdup(source.path(percentEncoded: false))
        defer { free(allocation) }
        let paths: [UnsafePointer<CChar>?] = [
            allocation.map { UnsafePointer($0) },
            allocation.map { UnsafePointer($0) }
        ]

        var firstReport = PWStitchReport()
        var firstError: UnsafeMutablePointer<CChar>?
        let firstSucceeded = paths.withUnsafeBufferPointer { buffer in
            PWStitchPanorama(
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
        #expect(bitmap.hasAlpha)
        var channelDifference = 0.0
        var brightness = 0.0
        var sampleCount = 0.0
        var transparentCount = 0
        var opaqueCount = 0
        for y in stride(from: 16, to: bitmap.pixelsHigh, by: 32) {
            for x in stride(from: 16, to: bitmap.pixelsWide, by: 32) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.alphaComponent < 0.01 {
                    transparentCount += 1
                } else if color.alphaComponent > 0.99 {
                    opaqueCount += 1
                }
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
        #expect(transparentCount > 0)
        #expect(opaqueCount > 0)
        #expect(channelDifference / sampleCount < 0.04)
        #expect(brightness / sampleCount > 0.08)

        var cachedReport = PWStitchReport()
        var cachedError: UnsafeMutablePointer<CChar>?
        let cachedSucceeded = paths.withUnsafeBufferPointer { buffer in
            PWStitchPanorama(
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

    @Test("A failed supplement is skipped while later supplements are registered")
    func failedSupplementDoesNotStopLaterSupplements() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Ring-Selection-Test-\(UUID())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let ringSource = directory.appending(path: "ring.jpg")
        let unrelatedSource = directory.appending(path: "unrelated.jpg")
        try writeTexturedImage(to: ringSource, seed: 0x6d2b79f5)
        try writeTexturedImage(to: unrelatedSource, seed: 0x12345678)
        let output = directory.appending(path: "result.png")
        let cache = directory.appending(path: "alignment.yml")
        let paths = [ringSource, ringSource, ringSource, unrelatedSource, ringSource]
            .map { strdup($0.path(percentEncoded: false)) }
        defer { paths.forEach { free($0) } }
        let sourcePaths: [UnsafePointer<CChar>?] = paths.map {
            $0.map { UnsafePointer($0) }
        }
        let automaticRoles: [UInt8] = [1, 1, 1, 2, 2]
        var report = PWStitchReport()
        var error: UnsafeMutablePointer<CChar>?
        defer { PWFreeString(error) }
        defer { PWFreeString(report.skippedImageDetails) }
        let succeeded = sourcePaths.withUnsafeBufferPointer { sources in
            automaticRoles.withUnsafeBufferPointer { roles in
                PWStitchPanorama(
                    sources.baseAddress,
                    nil,
                    roles.baseAddress,
                    Int32(sourcePaths.count),
                    cache.path(percentEncoded: false),
                    output.path(percentEncoded: false),
                    512,
                    nil,
                    nil,
                    nil,
                    &report,
                    &error
                )
            }
        }

        #expect(succeeded == 1)
        #expect(error == nil)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(report.coveragePercent > 0)
        #expect(report.ringImageCount == 3)
        #expect(report.usedSupplementalImageCount == 1)
        #expect(report.skippedImageDetails != nil)
        let skippedDetails = report.skippedImageDetails.map { String(cString: $0) }
        #expect(skippedDetails?.contains("3\t") == true)
        #expect(skippedDetails?.contains("4\t") != true)
        #expect(skippedDetails?.contains("Insufficient overlap matches") == true)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test("A red mask excludes repair image control points")
    func redMaskExcludesRepairControlPoints() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Repair-Mask-Test-\(UUID())"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "source.jpg")
        try writeTexturedImage(to: url)
        let size = 512
        let images = (0..<4).map { index in
            SourceImage(
                url: url, captureDate: nil, pixelWidth: size, pixelHeight: size,
                cameraModel: nil,
                lens: LensDescription(model: nil, focalLengthIn35mm: nil, kind: .fisheye),
                role: index == 3 ? .fillOnly : .alignment
            )
        }
        let repair = images[3]
        let red = try #require(SourceMaskRasterizer.applyingCircle(
            center: MaskPoint(x: 0.5, y: 0.5), radius: CGFloat(size),
            erasing: false, to: nil, width: size, height: size
        ))
        let engine = OpenCVPanoramaEngine()
        let panorama = PanoramaSet(images: images)
        let unmasked = try await engine.stitch(panorama, masks: [:], protectedMasks: [:]) { _, _ in }
        #expect(unmasked.usedSupplementalImageCount == 1)
        #expect(unmasked.warningMessage == nil)

        let masked = try await engine.stitch(panorama, masks: [repair.id: red], protectedMasks: [:]) { _, _ in }
        #expect(masked.ringImageCount == 3)
        #expect(masked.usedSupplementalImageCount == 0)
        #expect(masked.warningMessage?.contains("Insufficient overlap matches") == true)
        #expect(!masked.usedAlignmentCache)
    }

    @Test("A rejected local repair factor uses neutral when the global factor is worse")
    func repairRejectsWorseGlobalColorFactor() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Repair-Color-Test-\(UUID())"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let size = 512
        let ring = directory.appending(path: "ring.pgm")
        let repair = directory.appending(path: "repair.pgm")
        let mask = directory.appending(path: "green.pgm")
        let cache = directory.appending(path: "alignment.yml")
        let output = directory.appending(path: "result.png")
        let header = Data("P5\n\(size) \(size)\n255\n".utf8)
        try (header + Data(repeating: 200, count: size * size)).write(to: ring)
        var repairImage = header
        var maskImage = header
        for y in 0..<size {
            for x in 0..<size {
                let marked = (206..<306).contains(x) && (206..<306).contains(y)
                let center = (230..<282).contains(x) && (230..<282).contains(y)
                // A single local factor cannot improve both sides of the overlap.
                repairImage.append(center ? 185 : (x < 276 ? 190 : 220))
                maskImage.append(marked ? 255 : 0)
            }
        }
        try repairImage.write(to: repair)
        try maskImage.write(to: mask)

        // Fix the geometry and the global gain so this tests the renderer's decision.
        try """
        %YAML:1.2
        ---
        version: 7
        imageCount: 3
        width: 512
        height: 512
        rotations: !!opencv-matrix
          rows: 3
          cols: 9
          dt: d
          data: [1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1]
        roles: !!opencv-matrix
          rows: 1
          cols: 3
          dt: u
          data: [1, 1, 2]
        lens: !!opencv-matrix
          rows: 1
          cols: 6
          dt: d
          data: [1.7, 0, 0, 256, 256, 0]
        gains: !!opencv-matrix
          rows: 3
          cols: 3
          dt: d
          data: [1, 1, 1, 1, 1, 1, 1.4, 1.4, 1.4]
        """.write(to: cache, atomically: true, encoding: .utf8)

        let paths = [ring, ring, repair, mask].map { strdup($0.path(percentEncoded: false)) }
        defer { paths.forEach { free($0) } }
        let sources = paths.prefix(3).map { $0.map { UnsafePointer($0) } }
        let masks: [UnsafePointer<CChar>?] = [nil, nil, paths[3].map { UnsafePointer($0) }]
        var report = PWStitchReport()
        var error: UnsafeMutablePointer<CChar>?
        defer { PWFreeString(error) }
        defer { PWFreeString(report.skippedImageDetails) }
        let succeeded = PWStitchPanorama(
            sources, masks, nil, 3, cache.path(percentEncoded: false),
            output.path(percentEncoded: false), Int32(size), nil, nil, nil, &report, &error
        )

        try #require(succeeded == 1, Comment(rawValue: error.map { String(cString: $0) } ?? ""))
        #expect(report.usedAlignmentCache == 1)
        #expect(report.usedSupplementalImageCount == 1)
        let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: output)))
        let center = try #require(bitmap.colorAt(x: size / 2, y: size / 4))
        #expect(center.alphaComponent == 1)
        #expect(abs(center.redComponent * 255 - 185) < 1)
        #expect(abs(center.greenComponent * 255 - 185) < 1)
        #expect(abs(center.blueComponent * 255 - 185) < 1)
    }

    @Test("Skipped supplemental image warning names the source and reason")
    func skippedImageWarningNamesImageAndReason() throws {
        let first = image(enabled: true)
        var supplement = image(enabled: true)
        supplement.url = URL(fileURLWithPath: "/tmp/ceiling.jpg")
        let details = strdup("1\tInsufficient overlap with the ring.\n")
        defer { free(details) }

        let warning = OpenCVPanoramaEngine.skippedImageWarning(
            from: details.map { UnsafePointer($0) },
            images: [first, supplement]
        )

        #expect(warning?.contains("ceiling.jpg") == true)
        #expect(warning?.contains("Insufficient overlap with the ring.") == true)
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

    private func writeTexturedImage(
        to url: URL,
        seed: UInt32 = 0x6d2b79f5
    ) throws {
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
        var state = seed
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
