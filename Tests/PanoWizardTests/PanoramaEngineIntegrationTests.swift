import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PanoWizard

struct PanoramaEngineIntegrationTests {
    @Test
    func blendsRepairIntoFrozenLocalPanoramaView() throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }

        let package = URL(fileURLWithPath: packagePath)
        let projectData = try Data(
            contentsOf: package.appending(path: "project.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(PanoProject.self, from: projectData)
        let placement = try #require(project.nadirRepairPlacement)
        let repairImage = try #require(
            project.images.first { $0.id == placement.imageID }
        )
        let panoramaURL = package.appending(path: "panorama/result.jpg")
        let maskURL = package.appending(
            path: "masks/\(repairImage.id.uuidString).png"
        )
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-blended-nadir-overlay.png"
        )

        try OpenCVNadirRepairRegistrar.renderBlendedOverlay(
            panoramaURL: panoramaURL,
            repairImage: repairImage,
            exclusionMaskData: try? Data(contentsOf: maskURL),
            horizontalFieldOfView:
                project.stitching.inputHorizontalFieldOfView,
            placement: placement,
            outputURL: outputURL
        )

        let imageSource = try #require(
            CGImageSourceCreateWithURL(outputURL as CFURL, nil)
        )
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(
                imageSource,
                0,
                nil
            ) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1_600)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1_600)
        #expect((try Data(contentsOf: outputURL)).count > 100_000)
        print("PANOWIZARD_BLENDED_NADIR=\(outputURL.path())")
    }

    @Test
    func rendersRepairMaskWithoutRebuildingPanorama() throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }

        let package = URL(fileURLWithPath: packagePath)
        let projectData = try Data(
            contentsOf: package.appending(path: "project.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(PanoProject.self, from: projectData)
        let placement = try #require(project.nadirRepairPlacement)
        let repairImage = try #require(
            project.images.first { $0.id == placement.imageID }
        )
        let fullMask = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)],
            radius: CGFloat(max(
                repairImage.pixelWidth,
                repairImage.pixelHeight
            )),
            erasing: false,
            to: nil,
            width: repairImage.pixelWidth,
            height: repairImage.pixelHeight
        ))
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-masked-nadir-overlay.png"
        )

        try OpenCVNadirRepairRegistrar.renderOverlay(
            repairImage: repairImage,
            exclusionMaskData: fullMask,
            horizontalFieldOfView:
                project.stitching.inputHorizontalFieldOfView,
            placement: placement,
            outputURL: outputURL
        )

        let imageSource = try #require(
            CGImageSourceCreateWithURL(outputURL as CFURL, nil)
        )
        let image = try #require(
            CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        )
        var alpha = [UInt8](
            repeating: 0,
            count: image.width * image.height * 4
        )
        let rendered = alpha.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: image.width,
                    height: image.height
                )
            )
            return true
        }

        #expect(rendered)
        #expect(
            stride(from: 3, to: alpha.count, by: 4)
                .allSatisfy { alpha[$0] == 0 }
        )
    }

    @Test
    func stitchesConfiguredProjectWhenRequested() async throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }

        let package = URL(fileURLWithPath: packagePath)
        let projectData = try Data(
            contentsOf: package.appending(path: "project.json")
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(PanoProject.self, from: projectData)
        let masksDirectory = package.appending(
            path: "masks",
            directoryHint: .isDirectory
        )
        var masks: [UUID: Data] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(
            at: masksDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension.lowercased() == "png" {
                guard let id = UUID(
                    uuidString: file.deletingPathExtension().lastPathComponent
                ) else {
                    continue
                }
                masks[id] = try Data(contentsOf: file)
            }
        }

        let result = try await HuginOpenCVPanoramaEngine().stitch(
            project.panorama,
            masks: masks,
            configuration: project.stitching,
            cachedRigImageLines: [:]
        )

        #expect(FileManager.default.fileExists(atPath: result.url.path()))
        #expect((try Data(contentsOf: result.url)).count > 100_000)
        print("PANOWIZARD_INTEGRATION_RESULT=\(result.url.path())")

        if let repairImage = project.images.first(where: {
            $0.role == .fillOnly && $0.direction == .nadir
        }) {
            let repair = try #require(result.nadirRepair)
            #expect(repair.placement.imageID == repairImage.id)
            #expect(repair.placement.localHomography.count == 9)
            #expect(repair.placement.matchedFeatureCount >= 12)
            #expect(
                FileManager.default.fileExists(
                    atPath: repair.overlayURL.path()
                )
            )
            #expect((try Data(contentsOf: repair.overlayURL)).count > 100_000)
            let imageSource = try #require(
                CGImageSourceCreateWithURL(
                    repair.overlayURL as CFURL,
                    nil
                )
            )
            let properties = try #require(
                CGImageSourceCopyPropertiesAtIndex(
                    imageSource,
                    0,
                    nil
                ) as? [CFString: Any]
            )
            #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1_600)
            #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1_600)
            let homographyDescription = repair.placement.localHomography
                .map { String($0) }
                .joined(separator: ",")
            print(
                "PANOWIZARD_NADIR_OVERLAY=\(repair.overlayURL.path()) "
                    + "matches=\(repair.placement.matchedFeatureCount) "
                    + "homography=\(homographyDescription)"
            )
        } else {
            #expect(result.nadirRepair?.overlayURL == nil)
        }
    }
}
