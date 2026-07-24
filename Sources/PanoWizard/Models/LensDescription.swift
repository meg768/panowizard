import Foundation

struct LensDescription: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case rectilinear
        case fisheye
        case unknown
    }

    let model: String?
    let focalLengthIn35mm: Double?
    let kind: Kind

    var displayName: String {
        if let model, !model.isEmpty {
            return model
        }
        if let focalLengthIn35mm {
            return "\(focalLengthIn35mm.formatted(.number.precision(.fractionLength(0)))) mm"
        }
        return "Okänt objektiv"
    }
}
