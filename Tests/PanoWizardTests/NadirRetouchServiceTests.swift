import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PanoWizard

struct PoleRetouchServiceTests {
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
    func convertsPaintedAreaToTransparentOpenAIMask() throws {
        let directory = try temporaryDirectory()
        let apiMaskURL = directory.appending(path: "api-mask.png")
        let userMask = try #require(SourceMaskRasterizer.applyingRectangle(
            from: MaskPoint(x: 0.35, y: 0.35),
            to: MaskPoint(x: 0.65, y: 0.65),
            erasing: false,
            to: nil,
            width: 64,
            height: 64
        ))

        try PoleRetouchService().makeOpenAIEditMask(
            from: userMask,
            pole: .nadir,
            to: apiMaskURL,
            expectedSize: 64
        )

        let apiMask = try pixels(at: apiMaskURL)
        #expect(apiMask.width == 64)
        #expect(apiMask.height == 64)
        #expect(apiMask.pixel(x: 32, y: 32).3 == 0)
        #expect(apiMask.pixel(x: 4, y: 4).3 == 255)
    }

    @Test
    func maskedAIEditPreservesPixelsOutsideFeatheredArea() throws {
        let directory = try temporaryDirectory()
        let sourceURL = directory.appending(path: "source.png")
        let generatedURL = directory.appending(path: "generated.png")
        let previewURL = directory.appending(path: "preview.png")
        let preparedURL = directory.appending(path: "prepared.png")
        let panoramaURL = directory.appending(path: "panorama.png")
        let flattenedURL = directory.appending(path: "flattened.png")
        try writeImage(width: 64, height: 64, to: sourceURL) { _, _ in
            (12, 34, 56, 255)
        }
        try writeImage(width: 64, height: 64, to: generatedURL) { _, _ in
            (240, 10, 20, 255)
        }
        let userMask = try #require(SourceMaskRasterizer.applyingRectangle(
            from: MaskPoint(x: 0.375, y: 0.375),
            to: MaskPoint(x: 0.625, y: 0.625),
            erasing: false,
            to: nil,
            width: 64,
            height: 64
        ))

        try PoleRetouchService().prepareMaskedAIEdit(
            sourceURL: sourceURL,
            editedURL: generatedURL,
            userMaskData: userMask,
            pole: .zenith,
            previewURL: previewURL,
            preparedURL: preparedURL,
            expectedSize: 64,
            featherRadius: 4
        )

        let preview = try pixels(at: previewURL)
        let prepared = try pixels(at: preparedURL)
        #expect(preview.width == 64)
        #expect(preview.height == 64)
        #expect(preview.pixel(x: 4, y: 4) == (12, 34, 56, 255))
        #expect(preview.pixel(x: 32, y: 32).0 >= 235)
        #expect(prepared.pixel(x: 4, y: 4).3 == 0)
        #expect(prepared.pixel(x: 32, y: 32).3 >= 250)
        #expect((1...254).contains(Int(prepared.pixel(x: 23, y: 32).3)))

        try writeImage(width: 360, height: 180, to: panoramaURL) { _, _ in
            (0, 0, 0, 255)
        }
        try PoleRetouchService().flattenRetouches(
            panoramaURL: panoramaURL,
            nadirRetouchURL: nil,
            zenithRetouchURL: preparedURL,
            to: flattenedURL
        )
        let flattened = try pixels(at: flattenedURL)
        #expect(flattened.pixel(x: 180, y: 0).0 >= 230)
        #expect(flattened.pixel(x: 180, y: 30).0 == 0)
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
