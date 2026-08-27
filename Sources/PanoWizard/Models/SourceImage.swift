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
        case automatic
        case alignment
        case fillOnly

        var displayName: String {
            switch self {
            case .automatic:
                "Automatisk positionering"
            case .alignment:
                "Ingår i positionering"
            case .fillOnly:
                "Reparation"
            }
        }
    }

    let id: UUID
    var url: URL
    let captureDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let cameraModel: String?
    let lens: LensDescription
    var direction: Direction
    var role: Role
    var automaticRole: Role?
    var automaticDirection: Direction?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        captureDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        cameraModel: String?,
        lens: LensDescription,
        direction: Direction = .horizontal,
        role: Role = .automatic,
        automaticRole: Role? = nil,
        automaticDirection: Direction? = nil,
        isEnabled: Bool = true
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
        self.automaticRole = automaticRole
        self.automaticDirection = automaticDirection
        self.isEnabled = isEnabled
    }

    var filename: String {
        url.lastPathComponent
    }

    var effectiveRole: Role {
        role == .automatic ? automaticRole ?? .alignment : role
    }

    var effectiveDirection: Direction {
        role == .automatic ? automaticDirection ?? direction : direction
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, captureDate, pixelWidth, pixelHeight, cameraModel, lens
        case direction, role, automaticRole, automaticDirection, isEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        url = try values.decode(URL.self, forKey: .url)
        captureDate = try values.decodeIfPresent(Date.self, forKey: .captureDate)
        pixelWidth = try values.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try values.decode(Int.self, forKey: .pixelHeight)
        cameraModel = try values.decodeIfPresent(String.self, forKey: .cameraModel)
        lens = try values.decode(LensDescription.self, forKey: .lens)
        direction = try values.decode(Direction.self, forKey: .direction)
        role = try values.decode(Role.self, forKey: .role)
        automaticRole = try values.decodeIfPresent(
            Role.self, forKey: .automaticRole
        )
        automaticDirection = try values.decodeIfPresent(
            Direction.self, forKey: .automaticDirection
        )
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? true
    }
}

struct AutomaticPositioningDecision: Equatable, Sendable {
    let role: SourceImage.Role
    let direction: SourceImage.Direction
}
