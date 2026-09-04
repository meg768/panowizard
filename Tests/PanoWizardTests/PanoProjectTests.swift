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
