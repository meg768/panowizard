import Foundation

struct NadirRepairAdjustment: Codable, Equatable, Sendable {
    var translationX: Double
    var translationY: Double
    var rotationDegrees: Double
    var scale: Double

    static let identity = NadirRepairAdjustment(
        translationX: 0,
        translationY: 0,
        rotationDegrees: 0,
        scale: 1
    )

    var isIdentity: Bool {
        self == .identity
    }
}

struct NadirRepairPlacement: Codable, Equatable, Sendable {
    let imageID: UUID
    let localHomography: [Double]
    let matchedFeatureCount: Int
    let localViewFieldOfView: Double
    var manualAdjustment: NadirRepairAdjustment?
    var blendedPreview: Bool?

    init(
        imageID: UUID,
        localHomography: [Double],
        matchedFeatureCount: Int,
        localViewFieldOfView: Double,
        manualAdjustment: NadirRepairAdjustment? = nil,
        blendedPreview: Bool? = nil
    ) {
        precondition(localHomography.count == 9)
        self.imageID = imageID
        self.localHomography = localHomography
        self.matchedFeatureCount = matchedFeatureCount
        self.localViewFieldOfView = localViewFieldOfView
        self.manualAdjustment = manualAdjustment
        self.blendedPreview = blendedPreview
    }

    var isBlendedPreview: Bool {
        blendedPreview == true
    }
}
