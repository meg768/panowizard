import Foundation

protocol PanoramaEngine: Sendable {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> PanoramaStitchResult
}

struct PanoramaStitchResult: Sendable {
    let url: URL
    let coveragePercent: Double
    let holeCount: Int
    let usedAlignmentCache: Bool
}

enum PanoramaEngineError: LocalizedError {
    case insufficientImages
    case stitchingFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientImages:
            "Minst två aktiva bilder krävs för sammanfogning."
        case .stitchingFailed(let message):
            message
        }
    }
}
