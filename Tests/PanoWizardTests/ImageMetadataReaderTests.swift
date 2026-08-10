import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PanoWizard

struct ImageMetadataReaderTests {
    @Test
    func readsLensModelFromJPEGExifAuxiliaryMetadata() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 16 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(
            colorSpace: colorSpace,
            components: [0.2, 0.4, 0.6, 1]
        )!)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ))
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifFocalLength: 10.5
            ],
            kCGImagePropertyExifAuxDictionary: [
                kCGImagePropertyExifAuxLensModel:
                    "AF DX Fisheye-Nikkor 10.5mm f/2.8G ED"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFModel: "NIKON D70"
            ]
        ]
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))

        let result = try await ImageMetadataReader().readImage(at: url)

        #expect(result.cameraModel == "NIKON D70")
        #expect(
            result.lens.model
                == "AF DX Fisheye-Nikkor 10.5mm f/2.8G ED"
        )
        #expect(result.lens.focalLengthIn35mm == 10.5)
        #expect(result.lens.kind == .fisheye)
    }
}
