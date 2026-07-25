import Foundation

struct SourceImage: Codable, Identifiable, Hashable, Sendable {
    enum Direction: String, Codable, CaseIterable, Sendable {
        case horizontal
        case zenith
        case nadir

        var displayName: String {
            switch self {
            case .horizontal: "Horisontell"
            case .zenith: "Zenit"
            case .nadir: "Nadir"
            }
        }
    }

    enum Role: String, Codable, Sendable {
        case alignment
        case fillOnly

        var displayName: String {
            switch self {
            case .alignment:
                "Ingår i positionering"
            case .fillOnly:
                "Reparation"
            }
        }
    }

    let id: UUID
    let url: URL
    let captureDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let cameraModel: String?
    let lens: LensDescription
    var direction: Direction
    var role: Role

    init(
        id: UUID = UUID(),
        url: URL,
        captureDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        cameraModel: String?,
        lens: LensDescription,
        direction: Direction = .horizontal,
        role: Role = .alignment
    ) {
        self.id = id
        self.url = url
        self.captureDate = captureDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.cameraModel = cameraModel
        self.lens = lens
        self.direction = direction
        self.role = role
    }

    var filename: String {
        url.lastPathComponent
    }
}
