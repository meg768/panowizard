import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PanoWizard

struct PanoramaEngineIntegrationTests {
    @Test
    func circularMaskStaysCircularOnLandscapeImages() throws {
        let width = 300
        let height = 100
        let data = try #require(SourceMaskRasterizer.applyingCircle(
            center: MaskPoint(x: 0.5, y: 0.5),
            radius: 25,
            erasing: false,
            to: nil,
            width: width,
            height: height
        ))
        let mask = try #require(SourceMaskRasterizer.exclusionMap(
            from: data,
            width: width,
            height: height
        ))

        #expect(mask.contains(CGPoint(x: 150, y: 50), safetyRadius: 0))
        #expect(mask.contains(CGPoint(x: 174, y: 50), safetyRadius: 0))
        #expect(mask.contains(CGPoint(x: 150, y: 74), safetyRadius: 0))
        #expect(!mask.contains(CGPoint(x: 176, y: 50), safetyRadius: 0))
        #expect(!mask.contains(CGPoint(x: 150, y: 76), safetyRadius: 0))
    }

    @Test
    func exportsSelfContainedInteractiveHTML() async throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else {
            return
        }
        let package = URL(fileURLWithPath: packagePath)
        let panoramaURL = package.appending(path: "panorama/result.jpg")
        guard FileManager.default.fileExists(atPath: panoramaURL.path) else {
            return
        }
        let overlayURL = package.appending(path: "panorama/nadir-overlay.png")
        let zenithOverlayURL = package.appending(
            path: "panorama/zenith-overlay.png"
        )
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-panorama.html"
        )

        try await FilePanoramaExporter().exportHTML(
            panoramaURL: panoramaURL,
            nadirOverlayURL: FileManager.default.fileExists(
                atPath: overlayURL.path
            ) ? overlayURL : nil,
            zenithOverlayURL: FileManager.default.fileExists(
                atPath: zenithOverlayURL.path
            ) ? zenithOverlayURL : nil,
            title: "Pano <Wizard>",
            initialViewpoint: PanoramaViewpoint(
                yawRadians: 0.42,
                pitchRadians: -0.17,
                verticalFieldOfViewDegrees: 61
            ),
            to: outputURL
        )

        let html = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(html.contains("<title>Pano &lt;Wizard&gt;</title>"))
        #expect(html.contains("data:image/jpeg;base64,"))
        #expect(html.contains("getContext(\"webgl\")"))
        #expect(html.contains("zenithRepair"))
        #expect(html.contains("let y=0.42,"))
        #expect(html.contains("p=-0.17,"))
        #expect(html.contains("f=61.0*PI/180"))
        #expect((try Data(contentsOf: outputURL)).count > 100_000)
        print("PANOWIZARD_HTML_EXPORT=\(outputURL.path)")
    }

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
        var placement = try #require(project.nadirRepairPlacement)
        var adjustment = placement.manualAdjustment ?? .identity
        adjustment.cornerOffsets = [
            -4, 3,
            5, -2,
            6, 4,
            -3, 5
        ]
        placement.manualAdjustment = adjustment
        placement.contentBounds =
            OpenCVNadirRepairRegistrar.alphaContentBounds(
                at: package.appending(path: "panorama/nadir-overlay.png")
            ) ?? [0.2, 0.2, 0.6, 0.6]
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
        print("PANOWIZARD_BLENDED_NADIR=\(outputURL.path(percentEncoded: false))")
    }

    @Test
    func blendsZenithRepairIntoFrozenLocalPanoramaView() throws {
        guard let packagePath = ProcessInfo.processInfo.environment[
            "PANOWIZARD_INTEGRATION_PROJECT"
        ] else { return }
        let package = URL(fileURLWithPath: packagePath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(
            PanoProject.self,
            from: Data(contentsOf: package.appending(path: "project.json"))
        )
        let placement = try #require(project.zenithRepairPlacement)
        let repairImage = try #require(
            project.images.first { $0.id == placement.imageID }
        )
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-blended-zenith-overlay.png"
        )
        try OpenCVNadirRepairRegistrar.renderBlendedOverlay(
            panoramaURL: package.appending(path: "panorama/result.jpg"),
            repairImage: repairImage,
            exclusionMaskData: try? Data(contentsOf: package.appending(
                path: "masks/\(repairImage.id.uuidString).png"
            )),
            horizontalFieldOfView:
                project.stitching.inputHorizontalFieldOfView,
            pole: .zenith,
            placement: placement,
            outputURL: outputURL
        )
        #expect((try Data(contentsOf: outputURL)).count > 100_000)
        print("PANOWIZARD_BLENDED_ZENITH=\(outputURL.path)")
    }

    @Test
    func rendersRepairSelectionWithoutRebuildingPanorama() throws {
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
        let paintedSelection = try #require(SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)],
            radius: 180,
            erasing: false,
            to: nil,
            width: repairImage.pixelWidth,
            height: repairImage.pixelHeight
        ))
        let selectionMask = try #require(SourceMaskRasterizer.inverted(
            paintedSelection,
            width: repairImage.pixelWidth,
            height: repairImage.pixelHeight
        ))
        let outputURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-masked-nadir-overlay.png"
        )

        try OpenCVNadirRepairRegistrar.renderOverlay(
            repairImage: repairImage,
            exclusionMaskData: selectionMask,
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
        let alphaValues = stride(from: 3, to: alpha.count, by: 4).map {
            alpha[$0]
        }
        #expect(alphaValues.contains(0))
        #expect(alphaValues.contains { $0 > 0 })
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
        let controlPointMasksDirectory = package.appending(
            path: "control-point-masks",
            directoryHint: .isDirectory
        )
        var controlPointMasks: [UUID: Data] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(
            at: controlPointMasksDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension.lowercased() == "png" {
                guard let id = UUID(
                    uuidString: file.deletingPathExtension().lastPathComponent
                ) else {
                    continue
                }
                controlPointMasks[id] = try Data(contentsOf: file)
            }
        }
        var configuration = project.stitching
        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_FORCE_AUTOMATIC_ENGINE"
        ] == "1" {
            configuration.engine = .automatic
        }
        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_OPTIMIZE_ONLY"
        ] == "1" {
            let points = try #require(project.controlPoints)
            let optimized = try await HuginOpenCVPanoramaEngine()
                .optimizeControlPoints(
                    project.panorama,
                    controlPointMasks: controlPointMasks,
                    controlPoints: points,
                    configuration: configuration
                )
            #expect(!optimized.diagnostics.cleanedPoints.isEmpty)
            #expect(optimized.diagnostics.cleanedPoints.count <= points.count)
            #expect(
                optimized.diagnostics.cleanedPoints.allSatisfy {
                    $0.error?.isFinite == true
                }
            )
            let errors = optimized.diagnostics.cleanedPoints.compactMap(\.error)
            print(
                "PANOWIZARD_CONTROL_POINT_ERRORS="
                    + errors.map { String(format: "%.3f", $0) }
                        .joined(separator: ",")
            )
            let worst = optimized.diagnostics.cleanedPoints.enumerated()
                .sorted {
                    ($0.element.error ?? 0) > ($1.element.error ?? 0)
                }
                .prefix(10)
                .map {
                    let point = $0.element
                    return "\($0.offset + 1):"
                        + "\(point.firstImage + 1)-\(point.secondImage + 1)="
                        + String(format: "%.3f", point.error ?? 0)
                }
            print("PANOWIZARD_WORST_CONTROL_POINTS=\(worst.joined(separator: ","))")
            return
        }
        let regenerateControlPoints = ProcessInfo.processInfo.environment[
            "PANOWIZARD_REGENERATE_CONTROL_POINTS"
        ] == "1"
        let result = try await HuginOpenCVPanoramaEngine().stitch(
            project.panorama,
            masks: masks,
            controlPointMasks: controlPointMasks,
            controlPoints: regenerateControlPoints ? nil : project.controlPoints,
            configuration: configuration,
            cachedRigImageLines: [:]
        )
        let resultURL = try #require(result.url)

        #expect(FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)))
        #expect((try Data(contentsOf: resultURL)).count > 100_000)
        #expect(
            result.controlPointDiagnostics?.cleanedPoints.allSatisfy {
                $0.error?.isFinite == true
            } == true
        )
        print("PANOWIZARD_INTEGRATION_RESULT=\(resultURL.path(percentEncoded: false))")

        if ProcessInfo.processInfo.environment[
            "PANOWIZARD_VERIFY_CONTROL_POINT_EDITING"
        ] == "1" {
            let editedPoints = try #require(
                result.controlPointDiagnostics?.cleanedPoints
            )
            let editedResult = try await HuginOpenCVPanoramaEngine()
                .optimizeControlPoints(
                project.panorama,
                controlPointMasks: controlPointMasks,
                controlPoints: editedPoints,
                configuration: configuration
            )
            #expect(
                editedResult.diagnostics.cleanedPoints.count
                    == editedPoints.count
            )
            #expect(
                editedResult.diagnostics.cleanedPoints.allSatisfy {
                    $0.error?.isFinite == true
                }
            )
            print("PANOWIZARD_CONTROL_POINT_OPTIMIZATION=complete")
        }

        if let repairImage = project.images.first(where: {
            $0.role == .fillOnly && $0.direction == .nadir
        }) {
            let repair = try #require(result.nadirRepair)
            #expect(repair.placement.imageID == repairImage.id)
            #expect(repair.placement.localHomography.count == 9)
            #expect(repair.placement.matchedFeatureCount >= 12)
            #expect(repair.placement.contentBounds?.count == 4)
            #expect(
                FileManager.default.fileExists(
                    atPath: repair.overlayURL.path(percentEncoded: false)
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
                "PANOWIZARD_NADIR_OVERLAY=\(repair.overlayURL.path(percentEncoded: false)) "
                    + "matches=\(repair.placement.matchedFeatureCount) "
                    + "homography=\(homographyDescription)"
            )
        } else {
            #expect(result.nadirRepair?.overlayURL == nil)
        }
    }
}
