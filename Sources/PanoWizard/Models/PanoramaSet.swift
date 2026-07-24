import Foundation

struct PanoramaSet: Identifiable, Hashable, Sendable {
    let id: UUID
    let images: [SourceImage]

    init(id: UUID = UUID(), images: [SourceImage]) {
        self.id = id
        self.images = images
    }

    var title: String {
        guard let date = images.compactMap(\.captureDate).first else {
            return images.first?.url.deletingPathExtension().lastPathComponent ?? "Panorama"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var detail: String {
        "\(images.count) bilder"
    }
}
