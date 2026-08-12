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
        let imageURLs = Array(Set(urls.filter(isSupportedImage)))
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

    private func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
