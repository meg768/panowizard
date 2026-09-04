import Foundation

struct SourceImage: Codable, Identifiable, Hashable, Sendable {
    enum Direction: String, Codable, Sendable {
        case horizontal, zenith, nadir
    }

    enum Role: String, Codable, Sendable {
        case automatic, alignment, fillOnly
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
        direction = try values.decodeIfPresent(Direction.self, forKey: .direction)
            ?? .horizontal
        role = try values.decodeIfPresent(Role.self, forKey: .role) ?? .automatic
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
