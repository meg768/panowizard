import Foundation

struct PanoramaAdjustments: Codable, Equatable, Sendable {
    var exposure = 0.0
    var brightness = 0.0
    var contrast = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var whites = 0.0
    var blacks = 0.0
    var temperature = 0.0
    var tint = 0.0
    var vibrance = 0.0
    var saturation = 0.0

    static let neutral = PanoramaAdjustments()

    var isNeutral: Bool { self == .neutral }

    var sanitized: PanoramaAdjustments {
        PanoramaAdjustments(
            exposure: exposure.clamped(to: -3...3),
            brightness: brightness.clamped(to: -100...100),
            contrast: contrast.clamped(to: -100...100),
            highlights: highlights.clamped(to: -100...100),
            shadows: shadows.clamped(to: -100...100),
            whites: whites.clamped(to: -100...100),
            blacks: blacks.clamped(to: -100...100),
            temperature: temperature.clamped(to: -100...100),
            tint: tint.clamped(to: -100...100),
            vibrance: vibrance.clamped(to: -100...100),
            saturation: saturation.clamped(to: -100...100)
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
