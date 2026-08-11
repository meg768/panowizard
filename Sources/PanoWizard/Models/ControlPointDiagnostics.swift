import Foundation

struct ControlPointDiagnostics: Sendable {
    let images: [SourceImage]
    let rawPoints: [DiagnosticControlPoint]
    let cleanedPoints: [DiagnosticControlPoint]

    var pairs: [ControlPointPair] {
        let rawCounts = Dictionary(grouping: rawPoints, by: \.pair)
            .mapValues(\.count)
        let cleanedCounts = Dictionary(grouping: cleanedPoints, by: \.pair)
            .mapValues(\.count)
        return Set(rawCounts.keys).union(cleanedCounts.keys).sorted().map {
            ControlPointPair(
                firstImage: $0.firstImage,
                secondImage: $0.secondImage,
                rawCount: rawCounts[$0, default: 0],
                cleanedCount: cleanedCounts[$0, default: 0]
            )
        }
    }
}

struct DiagnosticControlPoint: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let firstImage: Int
    let secondImage: Int
    var firstX: Double
    var firstY: Double
    var secondX: Double
    var secondY: Double
    var error: Double?

    init(
        id: UUID = UUID(),
        firstImage: Int,
        secondImage: Int,
        firstX: Double,
        firstY: Double,
        secondX: Double,
        secondY: Double,
        error: Double? = nil
    ) {
        self.id = id
        self.firstImage = firstImage
        self.secondImage = secondImage
        self.firstX = firstX
        self.firstY = firstY
        self.secondX = secondX
        self.secondY = secondY
        self.error = error
    }

    var pair: ControlPointPair.ID {
        ControlPointPair.ID(
            firstImage: min(firstImage, secondImage),
            secondImage: max(firstImage, secondImage)
        )
    }
}

struct ControlPointPair: Identifiable, Hashable, Comparable, Sendable {
    struct ID: Hashable, Comparable, Sendable {
        let firstImage: Int
        let secondImage: Int

        static func < (lhs: ID, rhs: ID) -> Bool {
            (lhs.firstImage, lhs.secondImage)
                < (rhs.firstImage, rhs.secondImage)
        }
    }

    let firstImage: Int
    let secondImage: Int
    let rawCount: Int
    let cleanedCount: Int

    var id: ID {
        ID(firstImage: firstImage, secondImage: secondImage)
    }

    static func < (lhs: ControlPointPair, rhs: ControlPointPair) -> Bool {
        lhs.id < rhs.id
    }
}
