import Foundation

struct RetouchPatch: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case ai
        case manual

        var displayName: String { self == .ai ? "AI Patch" : "Manual Patch" }
    }

    var id: UUID
    var kind: Kind
    var viewpoint: PanoramaViewpoint
    var isEnabled: Bool
    var prompt: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        viewpoint: PanoramaViewpoint,
        isEnabled: Bool = true,
        prompt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.viewpoint = viewpoint
        self.isEnabled = isEnabled
        self.prompt = prompt
    }
}

struct PanoProject: Codable, Equatable, Sendable {
    static let currentFormatVersion = 10

    var formatVersion: Int
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var images: [SourceImage]
    var retouchPatches: [RetouchPatch]
    var previewViewpoint: PanoramaViewpoint?
    var panoramaAdjustments: PanoramaAdjustments

    init(
        formatVersion: Int = Self.currentFormatVersion,
        id: UUID = UUID(),
        title: String = "Untitled Panorama",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        images: [SourceImage] = [],
        retouchPatches: [RetouchPatch] = [],
        previewViewpoint: PanoramaViewpoint? = nil,
        panoramaAdjustments: PanoramaAdjustments = .neutral
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.title = title
        self.createdAt = Self.secondPrecision(createdAt)
        self.modifiedAt = Self.secondPrecision(modifiedAt)
        self.images = images
        self.retouchPatches = retouchPatches
        self.previewViewpoint = previewViewpoint
        self.panoramaAdjustments = panoramaAdjustments
    }

    var panorama: PanoramaSet {
        PanoramaSet(id: id, images: images)
    }

    mutating func replaceImages(_ images: [SourceImage]) {
        self.images = images
        touch()
        if title == "Untitled Panorama", let first = images.first {
            title = first.captureDate?.formatted(
                date: .abbreviated,
                time: .omitted
            ) ?? first.url.deletingPathExtension().lastPathComponent
        }
    }

    mutating func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
        touch()
    }

    mutating func toggleImageEnabled(_ imageID: UUID) {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else {
            return
        }
        images[index].isEnabled.toggle()
        touch()
    }

    mutating func rotateImageLeft(_ imageID: UUID) {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else {
            return
        }
        images[index].rotation = images[index].rotation.rotatedLeft
        touch()
    }

    mutating func setPanoramaAdjustments(_ adjustments: PanoramaAdjustments) {
        let sanitized = adjustments.sanitized
        guard panoramaAdjustments != sanitized else { return }
        panoramaAdjustments = sanitized
        touch()
    }

    mutating func setRetouchPatches(_ patches: [RetouchPatch]) {
        guard retouchPatches != patches else { return }
        retouchPatches = patches
        touch()
    }

    private mutating func touch() {
        modifiedAt = Self.secondPrecision(.now)
    }

    private static func secondPrecision(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}
