import Foundation
import Testing
@testable import PanoWizard

@Suite("Project format 7")
struct PanoProjectTests {
    @Test("Round-trip keeps sources and automatic metadata")
    func roundTrip() throws {
        let image = sourceImage()
        let project = PanoProject(images: [image])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            PanoProject.self,
            from: encoder.encode(project)
        )

        #expect(decoded == project)
        #expect(decoded.formatVersion == 7)
    }

    @Test("Version 6 engine fields migrate while composition roles survive")
    func legacyCompositionRolesSurviveMigration() throws {
        let id = UUID()
        let imageID = UUID()
        let json = """
        {
          "formatVersion": 6,
          "id": "\(id.uuidString)",
          "title": "Äldre projekt",
          "createdAt": "2026-01-01T00:00:00Z",
          "modifiedAt": "2026-01-01T00:00:00Z",
          "stitching": {"projection":"equirectangular","lensProfile":"sigma8DX"},
          "controlPoints": [{"firstImage":0,"secondImage":1}],
          "nadirRepairPlacement": {"imageID":"\(imageID.uuidString)"},
          "images": [{
            "id": "\(imageID.uuidString)",
            "url": "file:///tmp/source.jpg",
            "captureDate": null,
            "pixelWidth": 100,
            "pixelHeight": 80,
            "cameraModel": null,
            "lens": {"model":null,"focalLengthIn35mm":8,"kind":"fisheye"},
            "role": "fillOnly",
            "automaticRole": "alignment",
            "direction": "nadir",
            "isEnabled": true
          }]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var project = try decoder.decode(PanoProject.self, from: Data(json.utf8))
        project.migrateToCurrentFormat()

        #expect(project.formatVersion == 7)
        #expect(project.images.count == 1)
        #expect(project.images[0].id == imageID)
        #expect(project.images[0].isEnabled)
        #expect(project.images[0].effectiveRole == .fillOnly)
    }

    @Test("Removing a source remains safe")
    func removeSource() {
        let first = sourceImage()
        let second = sourceImage()
        var project = PanoProject(images: [first, second])

        project.removeImage(at: 0)

        #expect(project.images.map(\.id) == [second.id])
    }

    @Test("Project package keeps original AI results separate from applied patches")
    func storesOriginalAIRetouchResults() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Project-Test-\(UUID())",
            directoryHint: .isDirectory
        )
        let projectURL = directory.appending(
            path: "Retouch.pw",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let nadirPatch = Data([1, 2, 3])
        let nadirOriginal = Data([4, 5, 6])
        let zenithPatch = Data([7, 8, 9])
        let zenithOriginal = Data([10, 11, 12])
        let document = PanoProjectDocument(
            nadirRetouchData: nadirPatch,
            zenithRetouchData: zenithPatch,
            nadirAIRetouchResultData: nadirOriginal,
            zenithAIRetouchResultData: zenithOriginal
        )

        try document.writeAtomically(to: projectURL)
        let restored = try PanoProjectDocument(contentsOf: projectURL)

        #expect(restored.nadirRetouchData == nadirPatch)
        #expect(restored.zenithRetouchData == zenithPatch)
        #expect(restored.nadirAIRetouchResultData == nadirOriginal)
        #expect(restored.zenithAIRetouchResultData == zenithOriginal)
    }

    @Test("Applying AI retouch keeps generated image byte-for-byte")
    @MainActor
    func applyingAIRetouchKeepsGeneratedImage() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-AI-Apply-Test-\(UUID())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let editedURL = directory.appending(path: "edited.png")
        let preparedURL = directory.appending(path: "prepared.png")
        let edited = Data([21, 22, 23, 24])
        let prepared = Data([31, 32, 33, 34])
        try edited.write(to: editedURL)
        try prepared.write(to: preparedURL)
        let preview = AIRetouchPreview(
            pole: .nadir,
            directoryURL: directory,
            editedURL: editedURL,
            preparedURL: preparedURL
        )
        let model = AppModel.live()

        try model.applyAIRetouchPreview(preview)
        defer { model.removeRetouch(for: .nadir) }

        #expect(model.nadirAIRetouchResultData == edited)
        #expect(model.nadirRetouchData == prepared)
        #expect(model.nadirAIRetouchResultURL != model.nadirRetouchURL)
    }

    private func sourceImage() -> SourceImage {
        SourceImage(
            url: URL(fileURLWithPath: "/tmp/\(UUID()).jpg"),
            captureDate: nil,
            pixelWidth: 100,
            pixelHeight: 80,
            cameraModel: nil,
            lens: LensDescription(
                model: "Fisheye",
                focalLengthIn35mm: 8,
                kind: .fisheye
            )
        )
    }
}
