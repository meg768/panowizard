import Foundation

enum PanoramaPole: String, Codable, CaseIterable, Sendable {
    case zenith
    case nadir

    var pitchDegrees: Double { self == .zenith ? 90 : -90 }
    var displayName: String { self == .zenith ? "Zenit" : "Nadir" }
}

struct NadirRepairPlacement: Codable, Equatable, Sendable {
    let imageID: UUID
    var localHomography: [Double]
    let matchedFeatureCount: Int
    let localViewFieldOfView: Double
    /// The optimized source-lens HFOV used to defish this repair image.
    var sourceHorizontalFieldOfView: Double?
    var blendedPreview: Bool?
    var controlPoints: [DiagnosticControlPoint]?
    var sphericalProjection: Bool?

    init(
        imageID: UUID,
        localHomography: [Double],
        matchedFeatureCount: Int,
        localViewFieldOfView: Double,
        sourceHorizontalFieldOfView: Double? = nil,
        blendedPreview: Bool? = nil,
        controlPoints: [DiagnosticControlPoint]? = nil,
        sphericalProjection: Bool? = nil
    ) {
        precondition(localHomography.count == 9)
        self.imageID = imageID
        self.localHomography = localHomography
        self.matchedFeatureCount = matchedFeatureCount
        self.localViewFieldOfView = localViewFieldOfView
        self.sourceHorizontalFieldOfView = sourceHorizontalFieldOfView
        self.blendedPreview = blendedPreview
        self.controlPoints = controlPoints
        self.sphericalProjection = sphericalProjection
    }

    var isBlendedPreview: Bool {
        blendedPreview == true
    }
}
