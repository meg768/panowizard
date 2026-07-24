import Foundation

protocol PanoramaExporting: Sendable {
    func export(imageAt sourceURL: URL, to destinationURL: URL) async throws
}

struct FilePanoramaExporter: PanoramaExporting {
    func export(imageAt sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }.value
    }
}
