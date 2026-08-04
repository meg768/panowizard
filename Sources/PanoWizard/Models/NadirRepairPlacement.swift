import Foundation

enum PanoramaPole: String, Codable, CaseIterable, Sendable {
    case zenith
    case nadir

    var pitchDegrees: Double { self == .zenith ? 90 : -90 }
    var displayName: String { self == .zenith ? "Zenit" : "Nadir" }
}

struct NadirRepairAdjustment: Codable, Equatable, Sendable {
    var translationX: Double
    var translationY: Double
    var rotationDegrees: Double
    var scale: Double
    /// Top-left, top-right, bottom-right and bottom-left offsets in local pixels.
    var cornerOffsets: [Double]? = nil

    static let identity = NadirRepairAdjustment(
        translationX: 0,
        translationY: 0,
        rotationDegrees: 0,
        scale: 1,
        cornerOffsets: nil
    )

    var isIdentity: Bool {
        translationX == 0
            && translationY == 0
            && rotationDegrees == 0
            && scale == 1
            && (cornerOffsets?.allSatisfy { abs($0) < 0.001 } ?? true)
    }

    var resolvedCornerOffsets: [Double] {
        guard let cornerOffsets, cornerOffsets.count == 8 else {
            return Array(repeating: 0, count: 8)
        }
        return cornerOffsets
    }
}

struct NadirRepairPlacement: Codable, Equatable, Sendable {
    let imageID: UUID
    var localHomography: [Double]
    let matchedFeatureCount: Int
    let localViewFieldOfView: Double
    /// The optimized source-lens HFOV used to defish this repair image.
    var sourceHorizontalFieldOfView: Double?
    /// Normalized x, y, width and height of non-transparent overlay pixels.
    var contentBounds: [Double]?
    var manualAdjustment: NadirRepairAdjustment?
    var blendedPreview: Bool?
    var controlPoints: [DiagnosticControlPoint]?
    var sphericalProjection: Bool?

    init(
        imageID: UUID,
        localHomography: [Double],
        matchedFeatureCount: Int,
        localViewFieldOfView: Double,
        sourceHorizontalFieldOfView: Double? = nil,
        contentBounds: [Double]? = nil,
        manualAdjustment: NadirRepairAdjustment? = nil,
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
        self.contentBounds = contentBounds
        self.manualAdjustment = manualAdjustment
        self.blendedPreview = blendedPreview
        self.controlPoints = controlPoints
        self.sphericalProjection = sphericalProjection
    }

    var isBlendedPreview: Bool {
        blendedPreview == true
    }

    var resolvedContentBounds: [Double] {
        guard let contentBounds, contentBounds.count == 4 else {
            return [0, 0, 1, 1]
        }
        return contentBounds
    }
}
