import Foundation

protocol PanoramaGrouping: Sendable {
    func group(_ images: [SourceImage]) -> [PanoramaSet]
}

struct PanoramaGroupingService: PanoramaGrouping {
    let maximumGap: TimeInterval

    init(maximumGap: TimeInterval = 900) {
        self.maximumGap = maximumGap
    }

    func group(_ images: [SourceImage]) -> [PanoramaSet] {
        let sorted = images.sorted(by: Self.sortOrder)
        guard let first = sorted.first else { return [] }

        var groups: [[SourceImage]] = [[first]]
        for image in sorted.dropFirst() {
            guard let previous = groups.last?.last else { continue }
            if belongsTogether(previous, image) {
                groups[groups.count - 1].append(image)
            } else {
                groups.append([image])
            }
        }

        return groups.map { PanoramaSet(images: $0) }
    }

    private func belongsTogether(_ lhs: SourceImage, _ rhs: SourceImage) -> Bool {
        guard lhs.cameraModel == rhs.cameraModel,
              lhs.lens.model == rhs.lens.model else {
            return false
        }
        guard let leftDate = lhs.captureDate,
              let rightDate = rhs.captureDate else {
            return lhs.url.deletingLastPathComponent() == rhs.url.deletingLastPathComponent()
        }
        return rightDate.timeIntervalSince(leftDate) <= maximumGap
    }

    private static func sortOrder(_ lhs: SourceImage, _ rhs: SourceImage) -> Bool {
        switch (lhs.captureDate, rhs.captureDate) {
        case let (left?, right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
    }
}
