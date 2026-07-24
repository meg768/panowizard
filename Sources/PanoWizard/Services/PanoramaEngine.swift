import Foundation

protocol PanoramaEngine: Sendable {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult
}

struct PanoramaStitchResult: Sendable {
    let url: URL
    let rigImageLines: [UUID: String]
}

enum PanoramaEngineError: LocalizedError {
    case insufficientImages
    case stitchingFailed(String)
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .insufficientImages:
            "Minst två bilder krävs för sammanfogning."
        case .stitchingFailed(let message):
            message
        case .notInstalled:
            "Den nya stitchmotorn byggs separat och är inte inkopplad ännu."
        }
    }
}

/// The document editor is deliberately independent from the next stitching
/// implementation. This engine makes that boundary explicit and prevents any
/// archived panorama code from leaking into the clean restart.
struct StitchingUnavailableEngine: PanoramaEngine {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult {
        guard panorama.images.count >= 2 else {
            throw PanoramaEngineError.insufficientImages
        }
        throw PanoramaEngineError.notInstalled
    }
}
