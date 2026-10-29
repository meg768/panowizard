import AppKit
import Foundation
import Testing
@testable import PanoWizard

@Suite("Retouch patch editing")
struct RetouchPatchEditingTests {
    @Test("Editing replaces patches in place and preserves their state")
    @MainActor
    func replacesPatchesInPlace() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Patch-Edit-Test-\(UUID())",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let aiPatch = RetouchPatch(
            kind: .ai,
            viewpoint: PanoramaViewpoint(yawRadians: 0.4),
            isEnabled: false,
            prompt: "Old instruction"
        )
        let manualPatch = RetouchPatch(
            kind: .manual,
            viewpoint: PanoramaViewpoint(yawRadians: -0.7),
            isEnabled: false
        )
        let model = AppModel.live(
            project: PanoProject(retouchPatches: [aiPatch, manualPatch]),
            panoramaData: Data([0]),
            retouchPatchData: [
                aiPatch.id: Data([1]),
                manualPatch.id: Data([2]),
            ],
            aiRetouchMaskData: [aiPatch.id: Data([3])]
        )
        let replacementURL = directory.appending(path: "replacement.png")
        try patchPNGData().write(to: replacementURL)

        try await model.applyManualRetouchPatch(
            from: replacementURL,
            viewpoint: manualPatch.viewpoint,
            replacing: manualPatch
        )

        let preview = AIRetouchPreview(
            viewpoint: aiPatch.viewpoint,
            directoryURL: directory,
            editedURL: replacementURL,
            preparedURL: replacementURL,
            compositedURL: replacementURL
        )
        let newMask = Data([9, 8, 7])
        try await model.applyAIRetouchPreview(
            preview,
            mode: .repair,
            replacePrompt: "Updated replacement instruction",
            repairPrompt: "Updated repair instruction",
            maskData: newMask,
            replacing: aiPatch
        )

        #expect(model.retouchPatches.map(\.id) == [aiPatch.id, manualPatch.id])
        #expect(model.retouchPatches.allSatisfy { !$0.isEnabled })
        #expect(model.retouchPatches[0].aiRetouchMode == .repair)
        #expect(model.retouchPatches[0].replacePrompt == "Updated replacement instruction")
        #expect(model.retouchPatches[0].repairPrompt == "Updated repair instruction")
        #expect(model.aiRetouchMaskDataByPatchID[aiPatch.id] == newMask)
        #expect(model.retouchPatchData.keys.contains(aiPatch.id))
        #expect(model.retouchPatchData.keys.contains(manualPatch.id))
    }

    @Test("Creating a panorama requires confirmation for existing retouch")
    @MainActor
    func requiresConfirmationBeforeStitching() throws {
        let patch = RetouchPatch(kind: .manual, viewpoint: PanoramaViewpoint(), isEnabled: true)
        let images = (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/tmp/confirmation-source-\(index).jpg"),
                captureDate: nil, pixelWidth: 100, pixelHeight: 100,
                cameraModel: nil,
                lens: LensDescription(model: nil, focalLengthIn35mm: nil, kind: .unknown)
            )
        }
        let document = PanoProjectDocument(
            project: PanoProject(images: images, retouchPatches: [patch]),
            panoramaData: Data([0]), retouchPatchData: [patch.id: Data([1])]
        )
        let model = AppModel.live(
            project: document.project,
            panoramaData: document.panoramaData,
            retouchPatchData: document.retouchPatchData
        )
        let originalURL = model.stitchedResultURL
        let originalPatches = model.retouchPatches
        model.stitch()
        #expect(model.confirmsDiscardRetouchForStitch)
        #expect(model.phase == .ready)
        #expect(model.stitchedResultURL == originalURL)
        #expect(model.retouchPatches == originalPatches)
        #expect(model.retouchPatchData == document.retouchPatchData)

        // Cancelling does not remove patches; disabled patches still need a warning.
        model.confirmsDiscardRetouchForStitch = false
        for index in model.project.retouchPatches.indices {
            model.project.retouchPatches[index].isEnabled = false
        }
        model.stitch()
        #expect(model.confirmsDiscardRetouchForStitch)
        #expect(model.phase == .ready)
        #expect(model.retouchPatches.count == originalPatches.count)
    }

    @Test("Changing image inclusion keeps the finished panorama and retouch patches")
    @MainActor
    func imageInclusionChangesPreservePanoramaAndPatches() {
        let images = testSourceImages()
        let manualPatch = RetouchPatch(
            kind: .manual,
            viewpoint: PanoramaViewpoint(yawRadians: 0.2)
        )
        let aiPatch = RetouchPatch(
            kind: .ai,
            viewpoint: PanoramaViewpoint(yawRadians: -0.4),
            prompt: "Remove the lamp"
        )
        let manualData = Data([1, 2, 3])
        let aiData = Data([4, 5, 6])
        let aiMask = Data([7, 8, 9])
        let model = AppModel.live(
            project: PanoProject(
                images: images,
                retouchPatches: [manualPatch, aiPatch],
                panoramaAdjustments: PanoramaAdjustments(exposure: 0.4)
            ),
            panoramaData: Data([10, 11, 12]),
            retouchPatchData: [
                manualPatch.id: manualData,
                aiPatch.id: aiData
            ],
            aiRetouchMaskData: [aiPatch.id: aiMask]
        )
        let panoramaURL = model.stitchedResultURL

        model.toggleSourceImageEnabled(images[1].id)
        #expect(!model.project.images[1].isEnabled)
        model.toggleSourceImageEnabled(images[1].id)

        #expect(model.project.images[1].isEnabled)
        #expect(model.stitchedResultURL == panoramaURL)
        #expect(model.retouchPatches == [manualPatch, aiPatch])
        #expect(model.retouchPatchData == [
            manualPatch.id: manualData,
            aiPatch.id: aiData
        ])
        #expect(model.aiRetouchMaskDataByPatchID == [aiPatch.id: aiMask])
        #expect(model.project.panoramaAdjustments.exposure == 0.4)
    }

    @Test("A failed replacement stitch keeps the old panorama and retouch patches")
    @MainActor
    func failedReplacementKeepsPanoramaAndPatches() async throws {
        let images = testSourceImages()
        let patch = RetouchPatch(
            kind: .ai,
            viewpoint: PanoramaViewpoint(),
            prompt: "Remove the lamp"
        )
        let patchData = Data([1, 3, 5])
        let maskData = Data([2, 4, 6])
        let model = AppModel(
            project: PanoProject(images: images, retouchPatches: [patch]),
            importer: ImageImportService(metadataReader: ImageMetadataReader()),
            grouper: PanoramaGroupingService(),
            panoramaEngine: FailingPanoramaEngine(),
            exporter: FilePanoramaExporter(),
            panoramaData: Data([7, 8, 9]),
            retouchPatchData: [patch.id: patchData],
            aiRetouchMaskData: [patch.id: maskData]
        )
        let originalPanoramaURL = model.stitchedResultURL
        model.stitch()
        #expect(model.confirmsDiscardRetouchForStitch)

        model.stitchDiscardingRetouch()
        for _ in 0..<100 {
            if model.phase == .stitchFailed("Simulated stitch failure") { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.phase == .stitchFailed("Simulated stitch failure"))
        #expect(model.stitchedResultURL == originalPanoramaURL)
        #expect(model.retouchPatches == [patch])
        #expect(model.retouchPatchData == [patch.id: patchData])
        #expect(model.aiRetouchMaskDataByPatchID == [patch.id: maskData])
    }

    private func testSourceImages() -> [SourceImage] {
        (0..<2).map { index in
            SourceImage(
                url: URL(fileURLWithPath: "/tmp/retouch-preservation-\(index).jpg"),
                captureDate: nil,
                pixelWidth: 100,
                pixelHeight: 100,
                cameraModel: nil,
                lens: LensDescription(
                    model: nil,
                    focalLengthIn35mm: nil,
                    kind: .unknown
                )
            )
        }
    }

    private func patchPNGData() throws -> Data {
        guard let image = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: RetouchPatchService.patchSize,
            pixelsHigh: RetouchPatchService.patchSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = image.representation(using: .png, properties: [:]) else {
            throw RetouchPatchError.writeFailed
        }
        return data
    }
}

private actor FailingPanoramaEngine: PanoramaEngine {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> PanoramaStitchResult {
        throw PanoramaEngineError.stitchingFailed("Simulated stitch failure")
    }
}
