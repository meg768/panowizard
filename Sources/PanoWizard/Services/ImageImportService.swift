import Foundation
import UniformTypeIdentifiers

protocol ImageImporting: Sendable {
    func load(from urls: [URL]) async -> ImportResult
}

struct ImportResult: Sendable {
    let images: [SourceImage]
    let skippedFiles: Int
}

struct ImageImportService: ImageImporting {
    let metadataReader: any ImageMetadataReading

    func load(from urls: [URL]) async -> ImportResult {
        let imageURLs = collectImageURLs(from: urls)
        var images: [SourceImage] = []
        var skippedFiles = 0

        await withTaskGroup(of: SourceImage?.self) { group in
            for url in imageURLs {
                group.addTask {
                    try? await metadataReader.readImage(at: url)
                }
            }
            for await image in group {
                if let image {
                    images.append(image)
                } else {
                    skippedFiles += 1
                }
            }
        }

        return ImportResult(images: images, skippedFiles: skippedFiles)
    }

    private func collectImageURLs(from urls: [URL]) -> [URL] {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey, .contentTypeKey]
                let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
                let files = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: options
                )
                while let file = files?.nextObject() as? URL {
                    if isSupportedImage(file) {
                        candidates.append(file)
                    }
                }
            } else if isSupportedImage(url) {
                candidates.append(url)
            }
        }

        return Array(Set(candidates))
    }

    private func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
