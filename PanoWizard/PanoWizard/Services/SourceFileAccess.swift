import Foundation

/// Keeps user-granted source access alive for previews, stitching and trashing,
/// and restores only the bookmarks supplied by the opened project.
final class SourceFileAccess: @unchecked Sendable {
    static let shared = SourceFileAccess()
    private let lock = NSRecursiveLock()
    private var bookmarksByPath: [String: Data] = [:]
    private var activeURLs: [String: URL] = [:]

    struct PermissionRequired: LocalizedError {
        let sourceURLs: [URL]
        var sourceURL: URL { sourceURLs[0] }

        init(sourceURL: URL) { sourceURLs = [sourceURL] }
        init(sourceURLs: [URL]) { self.sourceURLs = sourceURLs }

        var errorDescription: String? {
            "PanoWizard needs permission to access the source images for this project."
        }
    }

    private init() {}

    func retain(_ url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        let key = url.standardizedFileURL.path
        guard activeURLs[key] == nil else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarksByPath[key] = data
            if accessed { activeURLs[key] = url }
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// App-scoped bookmarks can target folders. Their opaque data lives in the
    /// project package, not UserDefaults; restoring never invokes permission UI.
    @discardableResult
    func restore(_ bookmarks: [String: Data]) -> [String: Data] {
        lock.lock()
        defer { lock.unlock() }
        var refreshed = bookmarks
        for (key, data) in bookmarks {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            do {
                try retain(url)
                if let updated = bookmarksByPath[url.standardizedFileURL.path] {
                    refreshed.removeValue(forKey: key)
                    refreshed[url.standardizedFileURL.path] = updated
                }
            } catch { continue }
        }
        return refreshed
    }

    /// Include only grants covering this project's source files. Prefer an
    /// existing folder grant over redundant file grants; never request a parent
    /// folder merely to persist access already granted to individually chosen files.
    func bookmarks(for sourceURLs: [URL], preserving existing: [String: Data]) -> [String: Data] {
        lock.lock()
        defer { lock.unlock() }
        let available = existing.merging(bookmarksByPath) { _, current in current }
        var result: [String: Data] = [:]
        for sourceURL in sourceURLs where sourceURL.isFileURL {
            let path = sourceURL.standardizedFileURL.path
            let covering = available.keys.filter { path == $0 || path.hasPrefix($0 + "/") }
            // A broader grant may already cover several explicitly selected
            // folders. Keep that grant once, without expanding its authorization.
            if let key = covering.min(by: { $0.count < $1.count }) {
                result[key] = available[key]
            }
        }
        return result
    }

    /// Restore existing grants. Permission recovery is presented by the document
    /// window, so opening a readable project never launches an access panel.
    func authorizeIfNeeded(for url: URL) throws {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 1)
        } catch {
            if Self.isConfirmedMissing(url) { return }
            let failure = error as NSError
            if (failure.domain == NSCocoaErrorDomain
                && [CocoaError.fileReadNoPermission.rawValue,
                    CocoaError.fileWriteNoPermission.rawValue].contains(failure.code))
                || (failure.domain == NSPOSIXErrorDomain
                    && [Int(EACCES), Int(EPERM)].contains(failure.code)) {
                throw PermissionRequired(sourceURL: url)
            }
            throw error
        }
    }

    /// Permission bits and readable directory metadata do not establish a
    /// sandbox grant. Exercise the same file-open permission as ImageIO.
    static func canOpenSource(at url: URL) -> Bool {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 1)
            return true
        } catch {
            return false
        }
    }

    private static func isConfirmedMissing(_ url: URL) -> Bool {
        // Only preserve the original missing-file fallback after actually
        // enumerating the parent. An inaccessible directory is not a missing
        // image, and must never cause project images to be discarded.
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ) else { return false }
        return !children.contains { $0.lastPathComponent == url.lastPathComponent }
    }
}
