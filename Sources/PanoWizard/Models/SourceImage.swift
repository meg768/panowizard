import Foundation

struct SourceImage: Codable, Identifiable, Hashable, Sendable {
    enum Rotation: Int, Codable, CaseIterable, Sendable {
        case none = 0
        case left90 = 1
        case halfTurn = 2
        case right90 = 3

        var rotatedLeft: Rotation {
            Rotation(rawValue: (rawValue + 1) % 4) ?? .none
        }

        var swapsDimensions: Bool { rawValue.isMultiple(of: 2) == false }
    }

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
    var rotation: Rotation

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
        isEnabled: Bool = true,
        rotation: Rotation = .none
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
        self.rotation = rotation
    }

    var filename: String {
        url.lastPathComponent
    }

    var effectiveRole: Role {
        role == .automatic ? automaticRole ?? .alignment : role
    }

    var orientedPixelWidth: Int {
        rotation.swapsDimensions ? pixelHeight : pixelWidth
    }

    var orientedPixelHeight: Int {
        rotation.swapsDimensions ? pixelWidth : pixelHeight
    }

}
