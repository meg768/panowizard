import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PanoWizard

struct PoleRetouchServiceTests {
    @Test
    func poleIdentityRemainsExplicit() {
        #expect(PanoramaPole.zenith.rawValue == "zenith")
        #expect(PanoramaPole.zenith.localizedName == "zenith")
        #expect(PanoramaPole.zenith.pitchDegrees == 90)
        #expect(PanoramaPole.nadir.rawValue == "nadir")
        #expect(PanoramaPole.nadir.localizedName == "nadir")
        #expect(PanoramaPole.nadir.pitchDegrees == -90)
    }

    @Test
    func exportsRequestedRealNadirPlate() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let panoramaPath = environment["PANOWIZARD_NADIR_PANORAMA"],
              let outputPath = environment["PANOWIZARD_NADIR_OUTPUT"] else {
            return
        }
        try PoleRetouchService().exportPlate(
            panoramaURL: URL(fileURLWithPath: panoramaPath),
            repairOverlayURL: nil,
            existingRetouchURL: nil,
            pole: .nadir,
            to: URL(fileURLWithPath: outputPath)
        )
    }

    @Test
    func preparesRequestedRealAutomaticMask() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sourcePath = environment["PANOWIZARD_AI_SOURCE"],
              let outputPath = environment["PANOWIZARD_AI_AUTOMATIC_MASK"] else {
            return
        }
        let generated = try PoleRetouchService().prepareAIRetouchMask(
            from: URL(fileURLWithPath: sourcePath),
            existingMaskData: nil,
            pole: .nadir
        )
        let data = try #require(generated)
        try data.write(
            to: URL(fileURLWithPath: outputPath),
            options: .atomic
        )
    }

    @Test
    func preparesRequestedRealAIRetouchPatch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let panoramaPath = environment["PANOWIZARD_AI_PANORAMA"],
              let maskPath = environment["PANOWIZARD_AI_MASK"],
              let resultPath = environment["PANOWIZARD_AI_RESULT"],
              let outputPath = environment["PANOWIZARD_AI_OUTPUT_DIRECTORY"] else {
            return
        }
        let outputDirectory = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let sourceURL = outputDirectory.appending(path: "source.png")
        let overlayURL = outputDirectory.appending(path: "overlay.png")
        let previewURL = outputDirectory.appending(path: "preview.png")
        let flattenedURL = outputDirectory.appending(path: "flattened.png")
        let baselineURL = outputDirectory.appending(path: "baseline.png")
        let service = PoleRetouchService()
        try service.exportPlate(
            panoramaURL: URL(fileURLWithPath: panoramaPath),
            repairOverlayURL: nil,
            existingRetouchURL: nil,
            pole: .nadir,
            to: sourceURL
        )
        try service.prepareAIRetouchPatch(
            originalURL: sourceURL,
            editedURL: URL(fileURLWithPath: resultPath),
            maskData: try Data(contentsOf: URL(fileURLWithPath: maskPath)),
            pole: .nadir,
            overlayURL: overlayURL,
            previewURL: previewURL
        )
        try service.flattenRetouches(
            panoramaURL: URL(fileURLWithPath: panoramaPath),
            nadirRetouchURL: overlayURL,
            zenithRetouchURL: nil,
            to: flattenedURL
        )
        try service.flattenRetouches(
            panoramaURL: URL(fileURLWithPath: panoramaPath),
            nadirRetouchURL: nil,
            zenithRetouchURL: nil,
            to: baselineURL
        )
    }

    @Test
    func exportsNinetyDegreeNadirFaceFromEquirectangularPanorama() throws {
        let directory = try temporaryDirectory()
        let panoramaURL = directory.appending(path: "panorama.png")
        let plateURL = directory.appending(path: "nadir.png")
        try writeImage(width: 360, height: 180, to: panoramaURL) { x, y in
            (UInt8(x * 255 / 359), UInt8(y * 255 / 179), 0, 255)
        }

        try PoleRetouchService().exportPlate(
            panoramaURL: panoramaURL,
            repairOverlayURL: nil,
            existingRetouchURL: nil,
            pole: .nadir,
            to: plateURL,
            size: 64
        )

        let plate = try pixels(at: plateURL)
        #expect(plate.width == 64)
        #expect(plate.height == 64)
        let center = plate.pixel(x: 32, y: 32)
        #expect(Int(center.1) >= 248)
        let forwardEdge = plate.pixel(x: 31, y: 0)
        #expect((120...136).contains(Int(forwardEdge.0)))
        #expect((184...198).contains(Int(forwardEdge.1)))
    }

    @Test
    func importedPlateGetsTransparentFeatherWithoutChangingItsSize() throws {
        let directory = try temporaryDirectory()
        let sourceURL = directory.appending(path: "edited.png")
        let destinationURL = directory.appending(path: "prepared.png")
        try writeImage(width: 64, height: 64, to: sourceURL) { _, _ in
            (255, 0, 0, 255)
        }

        try PoleRetouchService().prepareImportedPlate(
            from: sourceURL,
            pole: .nadir,
            to: destinationURL,
            expectedSize: 64
        )

        let prepared = try pixels(at: destinationURL)
        #expect(prepared.pixel(x: 0, y: 32).3 == 0)
        #expect(prepared.pixel(x: 32, y: 32).3 == 255)
        #expect(prepared.pixel(x: 32, y: 32).0 == 255)
    }

    @Test
    func aiRetouchInputMakesOnlyPaintedPixelsTransparent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.png")
        let maskURL = directory.appending(path: "mask.png")
        try writeImage(width: 64, height: 64, to: sourceURL) { _, _ in
            (120, 80, 40, 255)
        }
        try writeImage(width: 64, height: 64, to: maskURL) { x, y in
            x == 32 && y == 32 ? (255, 0, 0, 255) : (0, 0, 0, 0)
        }

        let resultData = try PoleRetouchService().prepareAIRetouchInput(
            from: sourceURL,
            maskData: try Data(contentsOf: maskURL),
            pole: .nadir,
            expectedSize: 64
        )
        let resultURL = directory.appending(path: "result.png")
        try resultData.write(to: resultURL)
        let result = try pixels(at: resultURL)

        #expect(result.pixel(x: 32, y: 32) == (0, 0, 0, 0))
        #expect(result.pixel(x: 10, y: 10) == (120, 80, 40, 255))
    }

    @Test
    func aiRetouchMaskUsesTransparencyAndPreservesOpaqueBlack() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.png")
        let existingURL = directory.appending(path: "existing.png")
        try writeImage(width: 64, height: 64, to: sourceURL) { x, y in
            if (20..<32).contains(x), (20..<32).contains(y) {
                return (0, 0, 0, 0)
            }
            if (2..<8).contains(x), (2..<8).contains(y) {
                return (0, 0, 0, 255)
            }
            return (80, 100, 120, 255)
        }
        try writeImage(width: 64, height: 64, to: existingURL) { x, y in
            x == 50 && y == 50 ? (255, 0, 0, 255) : (0, 0, 0, 0)
        }

        let generated = try PoleRetouchService().prepareAIRetouchMask(
            from: sourceURL,
            existingMaskData: try Data(contentsOf: existingURL),
            pole: .nadir,
            expectedSize: 64
        )
        let data = try #require(generated)
        let outputURL = directory.appending(path: "mask.png")
        try data.write(to: outputURL)
        let mask = try pixels(at: outputURL)
        #expect(mask.pixel(x: 24, y: 24) == (255, 31, 20, 255))
        #expect(mask.pixel(x: 50, y: 50).3 == 255)
        #expect(mask.pixel(x: 2, y: 2).3 == 0)
        #expect(mask.pixel(x: 10, y: 10).3 == 0)
    }

    @Test
    func exportedPlatePreservesAlpha() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transparentURL = directory.appending(path: "transparent.png")
        let blackURL = directory.appending(path: "black.png")
        let transparentPlateURL = directory.appending(
            path: "transparent-plate.png"
        )
        let blackPlateURL = directory.appending(path: "black-plate.png")
        try writeImage(width: 64, height: 32, to: transparentURL) { _, _ in
            (0, 0, 0, 0)
        }
        try writeImage(width: 64, height: 32, to: blackURL) { _, _ in
            (0, 0, 0, 255)
        }

        let service = PoleRetouchService()
        try service.exportPlate(
            panoramaURL: transparentURL,
            repairOverlayURL: nil,
            existingRetouchURL: nil,
            pole: .nadir,
            to: transparentPlateURL,
            size: 32
        )
        try service.exportPlate(
            panoramaURL: blackURL,
            repairOverlayURL: nil,
            existingRetouchURL: nil,
            pole: .nadir,
            to: blackPlateURL,
            size: 32
        )

        #expect(try pixels(at: transparentPlateURL).pixel(x: 16, y: 16).3 == 0)
        #expect(try pixels(at: blackPlateURL).pixel(x: 16, y: 16).3 == 255)
    }

    @Test
    func aiRetouchPatchIsLocalAndRadiometricallyMatched() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appending(path: "original.png")
        let editedURL = directory.appending(path: "edited.png")
        let maskURL = directory.appending(path: "mask.png")
        let overlayURL = directory.appending(path: "overlay.png")
        let previewURL = directory.appending(path: "preview.png")
        let size = 256
        let isPainted: (Int, Int) -> Bool = { x, y in
            (96..<160).contains(x) && (96..<160).contains(y)
        }
        try writeImage(width: size, height: size, to: originalURL) { _, _ in
            (80, 100, 120, 255)
        }
        try writeImage(width: size, height: size, to: editedURL) { x, y in
            isPainted(x, y) ? (210, 190, 170, 255) : (100, 130, 160, 255)
        }
        try writeImage(width: size, height: size, to: maskURL) { x, y in
            isPainted(x, y) ? (255, 0, 0, 255) : (0, 0, 0, 0)
        }

        try PoleRetouchService().prepareAIRetouchPatch(
            originalURL: originalURL,
            editedURL: editedURL,
            maskData: try Data(contentsOf: maskURL),
            pole: .nadir,
            overlayURL: overlayURL,
            previewURL: previewURL,
            expectedSize: size
        )

        let overlay = try pixels(at: overlayURL)
        let preview = try pixels(at: previewURL)
        #expect(overlay.pixel(x: 128, y: 128) == (190, 160, 130, 255))
        #expect(preview.pixel(x: 128, y: 128) == (190, 160, 130, 255))
        #expect(overlay.pixel(x: 0, y: 0) == (0, 0, 0, 0))
        #expect(preview.pixel(x: 0, y: 0) == (80, 100, 120, 255))
        #expect((1..<255).contains(Int(overlay.pixel(x: 95, y: 128).3)))
    }

    @Test
    func flattenedRetouchAffectsNadirButNotHorizon() throws {
        let directory = try temporaryDirectory()
        let panoramaURL = directory.appending(path: "panorama.png")
        let sourcePlateURL = directory.appending(path: "source-plate.png")
        let preparedPlateURL = directory.appending(path: "plate.png")
        let flattenedURL = directory.appending(path: "flattened.png")
        try writeImage(width: 360, height: 180, to: panoramaURL) { _, _ in
            (0, 0, 0, 255)
        }
        try writeImage(width: 64, height: 64, to: sourcePlateURL) { _, _ in
            (255, 0, 0, 255)
        }
        try PoleRetouchService().prepareImportedPlate(
            from: sourcePlateURL,
            pole: .nadir,
            to: preparedPlateURL,
            expectedSize: 64
        )

        try PoleRetouchService().flattenRetouches(
            panoramaURL: panoramaURL,
            nadirRetouchURL: preparedPlateURL,
            zenithRetouchURL: nil,
            to: flattenedURL
        )

        let flattened = try pixels(at: flattenedURL)
        #expect(flattened.pixel(x: 180, y: 179).0 >= 248)
        #expect(flattened.pixel(x: 180, y: 90).0 == 0)
    }

    @Test
    func exportsAndFlattensZenithWithoutAffectingHorizon() throws {
        let directory = try temporaryDirectory()
        let panoramaURL = directory.appending(path: "panorama.png")
        let sourcePlateURL = directory.appending(path: "source-plate.png")
        let preparedPlateURL = directory.appending(path: "zenith-plate.png")
        let flattenedURL = directory.appending(path: "flattened.png")
        let exportedURL = directory.appending(path: "exported-zenith.png")
        try writeImage(width: 360, height: 180, to: panoramaURL) { x, y in
            (UInt8(x * 255 / 359), UInt8(y * 255 / 179), 0, 255)
        }

        try PoleRetouchService().exportPlate(
            panoramaURL: panoramaURL,
            repairOverlayURL: nil,
            existingRetouchURL: nil,
            pole: .zenith,
            to: exportedURL,
            size: 64
        )
        let exported = try pixels(at: exportedURL)
        #expect(Int(exported.pixel(x: 32, y: 32).1) <= 7)

        try writeImage(width: 64, height: 64, to: sourcePlateURL) { _, _ in
            (0, 0, 255, 255)
        }
        try PoleRetouchService().prepareImportedPlate(
            from: sourcePlateURL,
            pole: .zenith,
            to: preparedPlateURL,
            expectedSize: 64
        )
        try PoleRetouchService().flattenRetouches(
            panoramaURL: panoramaURL,
            nadirRetouchURL: nil,
            zenithRetouchURL: preparedPlateURL,
            to: flattenedURL
        )
        let flattened = try pixels(at: flattenedURL)
        #expect(flattened.pixel(x: 180, y: 0).2 >= 248)
        #expect(flattened.pixel(x: 180, y: 90).2 == 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizardTests/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func writeImage(
        width: Int,
        height: Int,
        to url: URL,
        pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
    ) throws {
        var bytes = Array(repeating: UInt8(0), count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                let index = (y * width + x) * 4
                bytes[index] = value.0
                bytes[index + 1] = value.1
                bytes[index + 2] = value.2
                bytes[index + 3] = value.3
            }
        }
        let image = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        let requiredImage = try #require(image)
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, requiredImage, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func pixels(at url: URL) throws -> TestImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = Array(repeating: UInt8(0), count: image.width * image.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }
        #expect(rendered)
        return TestImage(width: image.width, height: image.height, bytes: bytes)
    }
}

private struct TestImage {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * width + x) * 4
        return (
            bytes[index],
            bytes[index + 1],
            bytes[index + 2],
            bytes[index + 3]
        )
    }
}
