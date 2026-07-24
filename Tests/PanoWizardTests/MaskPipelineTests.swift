import Foundation
import ImageIO
import Testing
@testable import PanoWizard

struct MaskPipelineTests {
    @Test
    func savedProjectStitchesWhenPackageIsProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment[
            "PANOWIZARD_PROJECT_PACKAGE"
        ] else {
            return
        }
        let package = URL(fileURLWithPath: path, isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(
            PanoProject.self,
            from: Data(contentsOf: package.appending(path: "project.json"))
        )
        let maskDirectory = package.appending(
            path: "masks",
            directoryHint: .isDirectory
        )
        var masks: [UUID: Data] = [:]
        for image in project.images {
            let maskURL = maskDirectory.appending(path: "\(image.id.uuidString).png")
            if FileManager.default.fileExists(atPath: maskURL.path()) {
                masks[image.id] = try Data(contentsOf: maskURL)
            }
        }

        let result = try await HuginPanoramaEngine().stitch(
            project.panorama,
            masks: masks,
            configuration: project.stitching,
            cachedRigImageLines: Dictionary(uniqueKeysWithValues:
                (project.cachedRigImageLines ?? [:]).compactMap {
                    key, value in UUID(uuidString: key).map { ($0, value) }
                }
            )
        )

        #expect(FileManager.default.fileExists(atPath: result.url.path()))
        let renderedLayers = try FileManager.default.contentsOfDirectory(
            at: result.url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("layer")
                && ["tif", "tiff"].contains($0.pathExtension.lowercased())
        }
        #expect(
            renderedLayers.count
                == project.images.filter { $0.role == .alignment }.count
        )
    }

    @Test
    func huginAcceptsRasterMaskedSourceWhenSampleDirectoryIsProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment[
            "PANOWIZARD_SAMPLE_DIRECTORY"
        ] else {
            return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
            .filter {
                ["jpg", "jpeg", "tif", "tiff"].contains(
                    $0.pathExtension.lowercased()
                )
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let reader = ImageMetadataReader()
        var images: [SourceImage] = []
        for url in urls {
            images.append(try await reader.readImage(at: url))
        }
        if ProcessInfo.processInfo.environment["PANOWIZARD_FILL_LAST"] == "1",
           !images.isEmpty {
            images[images.count - 1].role = .fillOnly
        }
        let first = try #require(images.first)
        let mask = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.8)],
            radius: 30,
            erasing: false,
            to: nil,
            width: first.pixelWidth,
            height: first.pixelHeight
        ))

        let result = try await HuginPanoramaEngine().stitch(
            PanoramaSet(images: images),
            masks: [first.id: mask],
            configuration: .automatic,
            cachedRigImageLines: [:]
        )

        #expect(FileManager.default.fileExists(atPath: result.url.path()))
    }

    @Test
    func rasterMaskContainsTransparentAndPaintedPixels() throws {
        let data = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)],
            radius: 10,
            erasing: false,
            to: nil,
            width: 100,
            height: 100
        ))
        let source = try #require(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let providerData = try #require(image.dataProvider?.data)
        let bytes = CFDataGetBytePtr(providerData)
        let centerAlpha = bytes?[50 * image.bytesPerRow + 50 * 4 + 3]
        let cornerAlpha = bytes?[3]

        #expect(centerAlpha == 255)
        #expect(cornerAlpha == 0)
    }

    @Test
    func maskedSourceWriterTransfersMaskToAlpha() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "source.png")
        let outputURL = directory.appending(path: "masked.tif")
        try writeSolidImage(to: sourceURL)
        let mask = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)],
            radius: 10,
            erasing: false,
            to: nil,
            width: 100,
            height: 100
        ))

        try MaskedSourceImageWriter.write(
            sourceURL: sourceURL,
            maskData: mask,
            destinationURL: outputURL
        )

        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.alphaInfo != .none)
        #expect(image.width == 100)
        #expect(image.height == 100)
    }

    private func writeSolidImage(to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
