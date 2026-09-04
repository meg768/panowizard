import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PanoWizard

struct ImageMetadataReaderTests {
    @Test
    func imageImportDoesNotSearchDirectories() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedDirectory = directory.appendingPathComponent(
            "Reference",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: nestedDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let rootImage = directory.appendingPathComponent("original.jpg")
        let referenceImage = nestedDirectory.appendingPathComponent("Panorama.jpg")
        let importer = ImageImportService(metadataReader: StubImageMetadataReader())

        let directoryResult = await importer.load(from: [directory])
        #expect(directoryResult.images.isEmpty)
        #expect(directoryResult.skippedFiles == 0)

        let explicitResult = await importer.load(
            from: [rootImage, referenceImage]
        )
        #expect(
            Set(explicitResult.images.map(\.url))
                == Set([rootImage, referenceImage])
        )
    }

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

private struct StubImageMetadataReader: ImageMetadataReading {
    func readImage(at url: URL) async throws -> SourceImage {
        SourceImage(
            url: url,
            captureDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            cameraModel: nil,
            lens: LensDescription(
                model: nil,
                focalLengthIn35mm: nil,
                kind: .rectilinear
            )
        )
    }
}
