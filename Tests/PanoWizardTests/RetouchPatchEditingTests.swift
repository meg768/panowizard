import AppKit
import Foundation
import Testing
@testable import PanoWizard

@Suite("Retouch patch editing")
struct RetouchPatchEditingTests {
    @Test("Editing replaces patches in place and preserves their state")
    @MainActor
    func replacesPatchesInPlace() throws {
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

        try model.applyManualRetouchPatch(
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
        try model.applyAIRetouchPreview(
            preview,
            prompt: "Refined instruction",
            maskData: newMask,
            replacing: aiPatch
        )

        #expect(model.retouchPatches.map(\.id) == [aiPatch.id, manualPatch.id])
        #expect(model.retouchPatches.allSatisfy { !$0.isEnabled })
        #expect(model.retouchPatches[0].prompt == "Refined instruction")
        #expect(model.aiRetouchMaskDataByPatchID[aiPatch.id] == newMask)
        #expect(model.retouchPatchData.keys.contains(aiPatch.id))
        #expect(model.retouchPatchData.keys.contains(manualPatch.id))
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
