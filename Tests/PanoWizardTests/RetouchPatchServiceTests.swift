import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PanoWizard

struct RetouchPatchServiceTests {

    @Test
    func aiRetouchInputUsesOnlyExplicitMask() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.png")
        let maskURL = directory.appending(path: "mask.png")
        try writeImage(width: 64, height: 64, to: sourceURL) { x, y in
            if x == 20 && y == 20 {
                return (0, 0, 0, 0)
            }
            return (120, 80, 40, 255)
        }
        try writeImage(width: 64, height: 64, to: maskURL) { x, y in
            x == 32 && y == 32 ? (255, 0, 0, 255) : (0, 0, 0, 0)
        }

        let resultData = try RetouchPatchService().prepareAIRetouchInput(
            from: sourceURL,
            maskData: try Data(contentsOf: maskURL),
            expectedSize: 64
        )
        let resultURL = directory.appending(path: "result.png")
        try resultData.write(to: resultURL)
        let result = try pixels(at: resultURL)

        #expect(result.pixel(x: 32, y: 32) == (0, 0, 0, 0))
        #expect(result.pixel(x: 10, y: 10) == (120, 80, 40, 255))
        #expect(result.pixel(x: 20, y: 20) == (0, 0, 0, 255))
    }

    @Test
    func exportedPatchPreservesAlpha() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transparentURL = directory.appending(path: "transparent.png")
        let blackURL = directory.appending(path: "black.png")
        let transparentPatchURL = directory.appending(
            path: "transparent-patch.png"
        )
        let blackPatchURL = directory.appending(path: "black-patch.png")
        try writeImage(width: 64, height: 32, to: transparentURL) { _, _ in
            (0, 0, 0, 0)
        }
        try writeImage(width: 64, height: 32, to: blackURL) { _, _ in
            (0, 0, 0, 255)
        }

        let service = RetouchPatchService()
        try service.exportPatch(
            panoramaURL: transparentURL,
            viewpoint: PanoramaViewpoint(),
            to: transparentPatchURL,
            size: 32
        )
        try service.exportPatch(
            panoramaURL: blackURL,
            viewpoint: PanoramaViewpoint(),
            to: blackPatchURL,
            size: 32
        )

        #expect(try pixels(at: transparentPatchURL).pixel(x: 16, y: 16).3 == 0)
        #expect(try pixels(at: blackPatchURL).pixel(x: 16, y: 16).3 == 255)
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

        try RetouchPatchService().prepareAIRetouchPatch(
            originalURL: originalURL,
            editedURL: editedURL,
            maskData: try Data(contentsOf: maskURL),
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
    func arbitraryPatchUsesTheSavedViewpoint() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let panoramaURL = directory.appending(path: "panorama.png")
        let patchURL = directory.appending(path: "patch.png")
        let baseURL = directory.appending(path: "base.png")
        let renderedURL = directory.appending(path: "rendered.png")
        let viewpoint = PanoramaViewpoint(
            yawRadians: .pi / 2,
            pitchRadians: 0,
            verticalFieldOfViewDegrees: 70
        )
        try writeImage(width: 360, height: 180, to: panoramaURL) { x, y in
            (UInt8(x * 255 / 359), UInt8(y * 255 / 179), 40, 255)
        }
        try writeImage(width: 360, height: 180, to: baseURL) { _, _ in
            (0, 0, 0, 255)
        }

        try RetouchPatchService().exportPatch(
            panoramaURL: panoramaURL,
            viewpoint: viewpoint,
            to: patchURL,
            size: 64
        )
        let patch = RetouchPatch(kind: .manual, viewpoint: viewpoint)
        try RetouchPatchService().render(
            panoramaURL: baseURL,
            patches: [(patch, patchURL)],
            to: renderedURL,
            expectedPatchSize: 64
        )

        let source = try pixels(at: panoramaURL)
        let rendered = try pixels(at: renderedURL)
        let expected = source.pixel(x: 270, y: 90)
        let actual = rendered.pixel(x: 270, y: 90)
        #expect(abs(Int(expected.0) - Int(actual.0)) <= 2)
        #expect(abs(Int(expected.1) - Int(actual.1)) <= 2)
        #expect(rendered.pixel(x: 90, y: 90) == (0, 0, 0, 255))
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
