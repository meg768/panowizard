import Foundation

struct PanoProject: Codable, Equatable, Sendable {
    static let currentFormatVersion = 7
    static let oldestReadableFormatVersion = 6

    var formatVersion: Int
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var images: [SourceImage]
    var nadirAIRetouchPrompt: String?
    var zenithAIRetouchPrompt: String?
    var previewViewpoint: PanoramaViewpoint?

    init(
        formatVersion: Int = Self.currentFormatVersion,
        id: UUID = UUID(),
        title: String = "Namnlöst panorama",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        images: [SourceImage] = [],
        nadirAIRetouchPrompt: String? = nil,
        zenithAIRetouchPrompt: String? = nil,
        previewViewpoint: PanoramaViewpoint? = nil
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.title = title
        self.createdAt = Self.secondPrecision(createdAt)
        self.modifiedAt = Self.secondPrecision(modifiedAt)
        self.images = images
        self.nadirAIRetouchPrompt = nadirAIRetouchPrompt
        self.zenithAIRetouchPrompt = zenithAIRetouchPrompt
        self.previewViewpoint = previewViewpoint
    }

    var panorama: PanoramaSet {
        PanoramaSet(id: id, images: images)
    }

    mutating func replaceImages(_ images: [SourceImage]) {
        self.images = images
        touch()
        if title == "Namnlöst panorama", let first = images.first {
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

    func aiRetouchPrompt(for pole: PanoramaPole) -> String? {
        pole == .nadir ? nadirAIRetouchPrompt : zenithAIRetouchPrompt
    }

    mutating func setAIRetouchPrompt(
        _ prompt: String,
        for pole: PanoramaPole
    ) {
        guard aiRetouchPrompt(for: pole) != prompt else { return }
        if pole == .nadir {
            nadirAIRetouchPrompt = prompt
        } else {
            zenithAIRetouchPrompt = prompt
        }
        touch()
    }

    mutating func clearAIRetouchPrompt(for pole: PanoramaPole) {
        guard aiRetouchPrompt(for: pole) != nil else { return }
        if pole == .nadir {
            nadirAIRetouchPrompt = nil
        } else {
            zenithAIRetouchPrompt = nil
        }
        touch()
    }

    mutating func migrateToCurrentFormat() {
        formatVersion = Self.currentFormatVersion
    }

    private mutating func touch() {
        modifiedAt = Self.secondPrecision(.now)
    }

    private static func secondPrecision(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}
