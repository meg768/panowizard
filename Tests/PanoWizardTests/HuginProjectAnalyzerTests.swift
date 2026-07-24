import Foundation
import Testing
@testable import PanoWizard

struct HuginProjectAnalyzerTests {
    @Test
    func findsDownwardFacingImages() {
        let project = """
        p f2 w4000 h2000 v360
        i w2000 h3008 f3 v87 r0 p1.5 y0 n"ring-1.jpg"
        i w2000 h3008 f3 v87 r0 p2.0 y45 n"ring-2.jpg"
        i w2000 h3008 f3 v87 r60 p-89.5 y120 n"nadir-1.jpg"
        i w2000 h3008 f3 v87 r67 p-88.5 y-68 n"nadir-2.jpg"
        i w2000 h3008 f3 v87 r-65 p86.8 y-62 n"zenith.jpg"
        """

        let analysis = HuginProjectAnalyzer.analyze(project)

        #expect(analysis.images.count == 5)
        #expect(analysis.nadirImages.map(\.index) == [2, 3])
        #expect(analysis.nadirImages.map(\.pitch) == [-89.5, -88.5])
    }

    @Test
    func repairImageIsExcludedFromRigOptimization() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appending(path: "cleaned.pto")
        let rig = directory.appending(path: "rig.pto")
        let repaired = directory.appending(path: "repair.pto")
        try """
        p f2 w4000 h2000 v360
        i w100 h100 f3 v100 r0 p0 y0 n"0.tif"
        i w100 h100 f3 v=0 r0 p0 y90 n"1.tif"
        i w100 h100 f3 v=0 r0 p-90 y0 n"5.tif"
        c n0 N1 x1 y1 X2 Y2 t0
        c n1 N5 x1 y1 X2 Y2 t0
        """.write(to: source, atomically: true, encoding: .utf8)

        try HuginPanoramaEngine.makeRigOptimizationProject(
            from: source,
            to: rig,
            imageCount: 6,
            fillOnlyIndices: [5]
        )
        let rigText = try String(contentsOf: rig, encoding: .utf8)
        #expect(rigText.contains("c n0 N1"))
        #expect(!rigText.contains("c n1 N5"))
        #expect(!rigText.contains("v y5"))

        try HuginPanoramaEngine.makeFillImageOptimizationProject(
            rigProject: rig,
            controlPointProject: source,
            output: repaired,
            fillOnlyIndices: [5]
        )
        let repairText = try String(contentsOf: repaired, encoding: .utf8)
        #expect(repairText.contains("c n1 N5"))
        #expect(repairText.contains("v y5 p5 r5"))
        #expect(repairText.contains("TrX5 TrY5 TrZ5"))
        #expect(!repairText.contains("v y1 p1 r1"))
    }

    @Test
    func sixShotSeedUsesHuginCompatibleASCIIMinus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appending(path: "base.pto")
        let seeded = directory.appending(path: "seeded.pto")
        let images = (0..<6).map {
            #"i w100 h200 f3 v100 r0 p0 y0 n"\#($0).tif""#
        }
        try images.joined(separator: "\n").write(
            to: source,
            atomically: true,
            encoding: .utf8
        )

        let sourceImages = (0..<6).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/\(index).tif"),
                captureDate: nil,
                pixelWidth: 100,
                pixelHeight: 200,
                cameraModel: nil,
                lens: LensDescription(model: nil, focalLengthIn35mm: nil, kind: .fisheye),
                direction: index == 4 ? .zenith : (index == 5 ? .nadir : .horizontal)
            )
        }
        try HuginPanoramaEngine.seedImageDirections(
            from: source,
            to: seeded,
            images: sourceImages
        )
        let result = try String(contentsOf: seeded, encoding: .utf8)

        #expect(result.contains("p-90.0"))
        #expect(!result.contains("−"))
    }

    @Test
    func cachedRigReplacesOnlyAlignmentImageLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appending(path: "project.pto")
        try """
        i w100 h100 f3 v100 r0 p0 y0 n"ring.tif"
        i w100 h100 f3 v=0 r0 p-90 y0 n"fill.tif"
        """.write(to: project, atomically: true, encoding: .utf8)
        let ring = SourceImage(
            url: URL(fileURLWithPath: "/ring.tif"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: LensDescription(model: nil, focalLengthIn35mm: nil, kind: .fisheye)
        )
        let fill = SourceImage(
            url: URL(fileURLWithPath: "/fill.tif"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            cameraModel: nil,
            lens: LensDescription(model: nil, focalLengthIn35mm: nil, kind: .fisheye),
            direction: .nadir,
            role: .fillOnly
        )
        let cached = #"i w100 h100 f3 v100 r1 p2 y3 n"/ring.tif""#

        try HuginPanoramaEngine.applyCachedRigImageLines(
            to: project,
            images: [ring, fill],
            cachedLines: [ring.id: cached]
        )
        let result = try String(contentsOf: project, encoding: .utf8)

        #expect(result.contains(cached))
        #expect(result.contains(#"p-90 y0 n"fill.tif""#))
    }
}
