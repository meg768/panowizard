import Foundation
import Testing
@testable import PanoWizard

@Suite("Project format 10")
struct PanoProjectTests {
    @Test("Round-trip keeps sources, metadata, and adjustments")
    func roundTrip() throws {
        let image = sourceImage()
        let adjustments = PanoramaAdjustments(
            exposure: 0.75,
            contrast: 18,
            temperature: -12
        )
        let project = PanoProject(
            images: [image],
            panoramaAdjustments: adjustments
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            PanoProject.self,
            from: encoder.encode(project)
        )

        #expect(decoded == project)
        #expect(decoded.formatVersion == 10)
        #expect(decoded.panoramaAdjustments == adjustments)
    }

    @Test("Project reader rejects noncurrent formats")
    func rejectsNoncurrentFormat() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Version-Test-\(UUID())",
            directoryHint: .isDirectory
        )
        let projectURL = directory.appending(
            path: "Unsupported.pw",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: projectURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let project = PanoProject(
            formatVersion: 8,
            title: "Unsupported Project"
        )
        try encoder.encode(project).write(
            to: projectURL.appending(path: "project.json")
        )

        #expect(throws: (any Error).self) {
            try PanoProjectDocument(contentsOf: projectURL)
        }
    }

    @Test("Relative source paths remain stable when macOS saves the package")
    func relativeSourcePathsRemainStable() throws {
        var image = sourceImage()
        image.url = URL(string: "source.jpg")!
        let document = PanoProjectDocument(
            project: PanoProject(images: [image])
        )

        let wrapper = try document.packageFileWrapper()
        let projectData = try #require(
            wrapper.fileWrappers?["project.json"]?.regularFileContents
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let storedProject = try decoder.decode(PanoProject.self, from: projectData)

        #expect(storedProject.images.first?.url.relativeString == "source.jpg")
    }

    @Test("Reader recovers a same-directory source with an extra parent component")
    func recoversSameDirectorySourcePath() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-Source-Path-Test-\(UUID())",
            directoryHint: .isDirectory
        )
        let projectURL = directory.appending(
            path: "panowizard.pw",
            directoryHint: .isDirectory
        )
        let sourceURL = directory.appending(path: "source.jpg")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: projectURL,
            withIntermediateDirectories: true
        )
        try Data().write(to: sourceURL)

        var image = sourceImage()
        image.url = URL(string: "../source.jpg")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(PanoProject(images: [image])).write(
            to: projectURL.appending(path: "project.json")
        )

        let restored = try PanoProjectDocument(contentsOf: projectURL)

        #expect(restored.project.images.count == 1)
        #expect(restored.project.images[0].url == sourceURL)
    }

    @Test("Optional source access metadata preserves the complete project package")
    func sourceAccessMetadataRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "bookmark-package-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appending(path: "source.jpg")
        try Data([1, 2]).write(to: sourceURL)
        var image = sourceImage()
        image.url = sourceURL
        let patchID = UUID()
        let original = PanoProjectDocument(
            project: PanoProject(images: [image], retouchPatches: [
                RetouchPatch(id: patchID, kind: .manual, viewpoint: PanoramaViewpoint())
            ]),
            masks: [image.id: Data([3])],
            protectedMasks: [image.id: Data([4])],
            panoramaData: Data([5]),
            retouchPatchData: [patchID: Data([6])],
            aiRetouchMaskData: [patchID: Data([7])],
            sourceAccessBookmarks: [sourceURL.path: try sourceURL.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
            )]
        )
        let projectURL = root.appending(path: "RoundTrip.pw")
        try original.writeAtomically(to: projectURL)
        let restored = try PanoProjectDocument(contentsOf: projectURL)
        #expect(restored.project == original.project)
        #expect(restored.masks == original.masks)
        #expect(restored.protectedMasks == original.protectedMasks)
        #expect(restored.panoramaData == original.panoramaData)
        #expect(restored.retouchPatchData == original.retouchPatchData)
        #expect(restored.aiRetouchMaskData == original.aiRetouchMaskData)
        #expect(restored.sourceAccessBookmarks.keys.contains(sourceURL.path))
        let metadata = try #require(JSONSerialization.jsonObject(with:
            Data(contentsOf: projectURL.appending(path: "source-access.json"))) as? [String: Any])
        #expect(metadata["version"] as? Int == 1)
        #expect((metadata["bookmarks"] as? [String: String])?.count == 1)
        #expect(!FileManager.default.fileExists(atPath: projectURL.appending(path: "source.jpg").path))
    }

    @Test("Legacy packages need no source access metadata")
    func legacyPackageHasNoRequiredBookmarks() throws {
        let wrapper = try PanoProjectDocument().packageFileWrapper()
        #expect(wrapper.fileWrappers?["source-access.json"] == nil)
    }

    @Test("All inaccessible sources are collected before permission recovery")
    func collectsEveryPermissionFailure() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "denied-project-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var images: [SourceImage] = []
        for name in ["a.jpg", "b.jpg"] {
            let url = root.appending(path: name)
            try Data([1]).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
            var image = sourceImage()
            image.url = url
            images.append(image)
        }
        defer {
            for image in images {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: image.url.path)
            }
        }
        let projectURL = root.appending(path: "Denied.pw")
        try PanoProjectDocument(project: PanoProject(images: images)).writeAtomically(to: projectURL)
        do {
            _ = try PanoProjectDocument(contentsOf: projectURL)
            Issue.record("Both denied sources must be reported")
        } catch let error as SourceFileAccess.PermissionRequired {
            #expect(Set(error.sourceURLs) == Set(images.map(\.url)))
        }
    }

    @Test("Removing a source remains safe")
    func removeSource() {
        let first = sourceImage()
        let second = sourceImage()
        var project = PanoProject(images: [first, second])

        project.removeImage(at: 0)

        #expect(project.images.map(\.id) == [second.id])
    }

    @Test("Removing all sources clears derived state and preserves original files")
    @MainActor
    func removeAllSources() throws {
        var first = sourceImage()
        first.url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).jpg")
        let second = sourceImage()
        let original = Data([1, 2, 3, 4])
        try original.write(to: first.url)
        defer { try? FileManager.default.removeItem(at: first.url) }
        let model = AppModel.live(
            project: PanoProject(images: [first, second]),
            panoramaData: Data([5, 6, 7])
        )
        model.selectSourceImage(first.id)
        model.setSourceMasks(red: Data([8]), green: Data([9]), for: first.id)
        model.removeAllSourceImages()
        #expect(model.project.images.isEmpty)
        #expect(model.selection == nil)
        #expect(model.stitchedResultURL == nil)
        #expect(model.maskDataByImageID.isEmpty)
        #expect(model.protectedMaskDataByImageID.isEmpty)
        #expect(!model.canUndoMask)
        #expect(try Data(contentsOf: first.url) == original)
    }

    @Test("Number control selects and toggles its source image")
    @MainActor
    func selectAndToggleSource() {
        let first = sourceImage()
        let second = sourceImage()
        let model = AppModel.live(project: PanoProject(
            images: [first, second],
            panoramaAdjustments: PanoramaAdjustments(exposure: 1)
        ))

        model.selectAndToggleSourceImageEnabled(second.id)

        #expect(model.selection == .source(second.id))
        #expect(model.project.images[0].isEnabled)
        #expect(!model.project.images[1].isEnabled)
        #expect(model.panoramaAdjustments.isNeutral)
    }

    @Test("A saved panorama opens directly in Preview")
    @MainActor
    func savedPanoramaOpensInPreview() {
        let image = sourceImage()
        let model = AppModel.live(
            project: PanoProject(images: [image]),
            panoramaData: Data([1, 2, 3])
        )

        #expect(model.stitchedResultURL != nil)
        #expect(model.selection == .panorama)
    }

    @Test("Project package keeps patch images and AI masks separate")
    func storesRetouchPatches() throws {
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
        let aiPatch = RetouchPatch(
            kind: .ai,
            viewpoint: PanoramaViewpoint(
                yawRadians: 0.4,
                pitchRadians: -0.2,
                verticalFieldOfViewDegrees: 70
            ),
            prompt: "Remove the tripod"
        )
        let manualPatch = RetouchPatch(
            kind: .manual,
            viewpoint: PanoramaViewpoint(yawRadians: -1.1)
        )
        let aiImage = Data([1, 2, 3])
        let manualImage = Data([4, 5, 6])
        let aiMask = Data([7, 8, 9])
        let panorama = Data([10, 11, 12])
        let document = PanoProjectDocument(
            project: PanoProject(retouchPatches: [aiPatch, manualPatch]),
            panoramaData: panorama,
            retouchPatchData: [
                aiPatch.id: aiImage,
                manualPatch.id: manualImage
            ],
            aiRetouchMaskData: [aiPatch.id: aiMask]
        )

        try document.writeAtomically(to: projectURL)
        let restored = try PanoProjectDocument(contentsOf: projectURL)

        #expect(restored.project.retouchPatches == [aiPatch, manualPatch])
        #expect(restored.retouchPatchData[aiPatch.id] == aiImage)
        #expect(restored.retouchPatchData[manualPatch.id] == manualImage)
        #expect(restored.aiRetouchMaskData == [aiPatch.id: aiMask])
        #expect(restored.panoramaData == panorama)
        #expect(FileManager.default.fileExists(
            atPath: projectURL.appending(path: "panorama/result.png").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: projectURL.appending(path: "panorama/result.jpg").path
        ))
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
