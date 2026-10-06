import Foundation
import Testing
@testable import PanoWizard

struct SourceFileAccessTests {
    @Test("Source access requires an actual file read")
    func readableSource() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "source-access-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1, 2, 3]).write(to: url)
        #expect(SourceFileAccess.canOpenSource(at: url))
        try FileManager.default.removeItem(at: url)
        #expect(!SourceFileAccess.canOpenSource(at: url))
    }

    @Test("A directory is not readable source-image content")
    func directoryIsNotASource() {
        #expect(!SourceFileAccess.canOpenSource(
            at: FileManager.default.temporaryDirectory
        ))
    }

    @Test("Permission failure identifies the source for folder recovery")
    func permissionFailureIdentifiesSource() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "source-permission-\(UUID()).png")
        try Data([1]).write(to: url)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        do {
            try SourceFileAccess.shared.authorizeIfNeeded(for: url)
            Issue.record("An unreadable source must request permission recovery")
        } catch let error as SourceFileAccess.PermissionRequired {
            #expect(error.sourceURL == url)
            #expect(error.errorDescription ==
                "PanoWizard needs permission to access the source images for this project.")
        }
    }

    @Test("Confirmed missing files do not request permission recovery")
    func missingSourceIsNotAPermissionFailure() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "missing-source-\(UUID()).png")
        try SourceFileAccess.shared.authorizeIfNeeded(for: url)
    }


    @Test("Project bookmarks include only relevant grants and deduplicate folders")
    func projectBookmarksAreRelevant() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "grants-\(UUID())")
        let folder = root.appending(path: "sources")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = folder.appending(path: "a.png")
        let b = folder.appending(path: "b.png")
        let unrelated = root.appending(path: "unrelated.png")
        for url in [a, b, unrelated] { try Data([1]).write(to: url) }
        try SourceFileAccess.shared.retain(a)
        try SourceFileAccess.shared.retain(folder)
        try SourceFileAccess.shared.retain(unrelated)
        let bookmarks = SourceFileAccess.shared.bookmarks(for: [a, b], preserving: [:])
        #expect(Set(bookmarks.keys) == [folder.path])
    }

}
