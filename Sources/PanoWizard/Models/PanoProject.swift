import Foundation

struct PanoProject: Codable, Equatable, Sendable {
    static let currentFormatVersion = 5

    var formatVersion: Int
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var images: [SourceImage]
    var stitching: StitchingConfiguration
    var cachedRigImageLines: [String: String]?
    var cachedRigSignature: String?

    init(
        formatVersion: Int = Self.currentFormatVersion,
        id: UUID = UUID(),
        title: String = "Namnlöst panorama",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        images: [SourceImage] = [],
        stitching: StitchingConfiguration = .automatic,
        cachedRigImageLines: [String: String]? = nil,
        cachedRigSignature: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.title = title
        self.createdAt = Self.secondPrecision(createdAt)
        self.modifiedAt = Self.secondPrecision(modifiedAt)
        self.images = images
        self.stitching = stitching
        self.cachedRigImageLines = cachedRigImageLines
        self.cachedRigSignature = cachedRigSignature
    }

    var panorama: PanoramaSet {
        PanoramaSet(id: id, images: images)
    }

    mutating func replaceImages(_ images: [SourceImage]) {
        let oldGeometry = self.images.map { ($0.id, $0.direction, $0.role) }
        let newGeometry = images.map { ($0.id, $0.direction, $0.role) }
        if oldGeometry.elementsEqual(newGeometry, by: { left, right in
            left.0 == right.0 && left.1 == right.1 && left.2 == right.2
        }) == false {
            invalidateRigCache()
        }
        self.images = images
        modifiedAt = Self.secondPrecision(.now)

        if title == "Namnlöst panorama", let first = images.first {
            title = first.captureDate?.formatted(date: .abbreviated, time: .omitted)
                ?? first.url.deletingPathExtension().lastPathComponent
        }
    }

    mutating func setRole(_ role: SourceImage.Role, for imageID: UUID) {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else {
            return
        }
        images[index].role = role
        invalidateRigCache()
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func setDirection(_ direction: SourceImage.Direction, for imageID: UUID) {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else {
            return
        }
        images[index].direction = direction
        invalidateRigCache()
        modifiedAt = Self.secondPrecision(.now)
    }

    var rigSignature: String {
        let imagePart = images
            .filter { $0.role == .alignment }
            .map { "\($0.id.uuidString):\($0.direction.rawValue)" }
            .joined(separator: "|")
        return [
            imagePart,
            stitching.engine.rawValue,
            stitching.projection.rawValue,
            stitching.lensProfile.rawValue,
            String(stitching.inputHorizontalFieldOfView)
        ].joined(separator: "#")
    }

    mutating func invalidateRigCache() {
        cachedRigImageLines = nil
        cachedRigSignature = nil
    }

    private static func secondPrecision(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

struct StitchingConfiguration: Codable, Equatable, Sendable {
    enum Engine: String, Codable, Sendable {
        case automatic
        case openCV
        case hugin
    }

    enum Projection: String, Codable, Sendable {
        case automatic
        case cylindrical
        case equirectangular
    }

    enum LensProfile: String, Codable, CaseIterable, Sendable {
        case automatic
        case nikon105DX
        case sigma8DX
        case custom

        var displayName: String {
            switch self {
            case .automatic: "Automatiskt från EXIF"
            case .nikon105DX: "Nikon 10,5 mm · DX"
            case .sigma8DX: "Sigma 8 mm · DX"
            case .custom: "Eget"
            }
        }

        var defaultHorizontalFieldOfView: Double? {
            switch self {
            case .automatic, .custom: nil
            case .nikon105DX: 100
            case .sigma8DX: 120
            }
        }
    }

    var engine: Engine
    var projection: Projection
    var lensProfile: LensProfile
    var inputHorizontalFieldOfView: Double

    static let automatic = StitchingConfiguration(
        engine: .automatic,
        projection: .automatic,
        lensProfile: .automatic,
        inputHorizontalFieldOfView: 90
    )
}
