import Foundation

struct PanoProject: Codable, Equatable, Sendable {
    static let currentFormatVersion = 5

    var formatVersion: Int
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var images: [SourceImage]
    var stitching: StitchingConfiguration
    var cachedRigImageLines: [String: String]?
    var cachedRigSignature: String?
    var controlPoints: [DiagnosticControlPoint]?
    var controlPointMaskSignature: String?
    var nadirRepairPlacement: NadirRepairPlacement?
    var zenithRepairPlacement: NadirRepairPlacement?
    var previewViewpoint: PanoramaViewpoint?

    init(
        formatVersion: Int = Self.currentFormatVersion,
        id: UUID = UUID(),
        title: String = "Namnlöst panorama",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        images: [SourceImage] = [],
        stitching: StitchingConfiguration = .automatic,
        cachedRigImageLines: [String: String]? = nil,
        cachedRigSignature: String? = nil,
        controlPoints: [DiagnosticControlPoint]? = nil,
        controlPointMaskSignature: String? = nil,
        nadirRepairPlacement: NadirRepairPlacement? = nil,
        zenithRepairPlacement: NadirRepairPlacement? = nil,
        previewViewpoint: PanoramaViewpoint? = nil
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.title = title
        self.createdAt = Self.secondPrecision(createdAt)
        self.modifiedAt = Self.secondPrecision(modifiedAt)
        self.images = images
        self.stitching = stitching
        self.cachedRigImageLines = cachedRigImageLines
        self.cachedRigSignature = cachedRigSignature
        self.controlPoints = controlPoints
        self.controlPointMaskSignature = controlPointMaskSignature
        self.nadirRepairPlacement = nadirRepairPlacement
        self.zenithRepairPlacement = zenithRepairPlacement
        self.previewViewpoint = previewViewpoint
        removeUnsupportedControlPoints()
    }

    var panorama: PanoramaSet {
        PanoramaSet(id: id, images: images)
    }

    mutating func replaceImages(_ images: [SourceImage]) {
        let oldImages = self.images
        let oldControlPoints = controlPoints
        let oldGeometry = oldImages.map { ($0.id, $0.role) }
        let newGeometry = images.map { ($0.id, $0.role) }
        if oldGeometry.elementsEqual(newGeometry, by: { left, right in
            left.0 == right.0 && left.1 == right.1
        }) == false {
            invalidateRigCache()
            nadirRepairPlacement = nil
        }
        let oldFilenameCounts = Dictionary(grouping: oldImages, by: \.filename)
            .mapValues(\.count)
        let newFilenameIndices = Dictionary(grouping: images.enumerated()) {
            $0.element.filename
        }.compactMapValues { matches in
            matches.count == 1 ? matches[0].offset : nil
        }
        func replacementIndex(for oldImage: SourceImage) -> Int? {
            guard oldFilenameCounts[oldImage.filename] == 1 else { return nil }
            return newFilenameIndices[oldImage.filename]
        }
        controlPoints = oldControlPoints?.compactMap { point in
            guard oldImages.indices.contains(point.firstImage),
                  oldImages.indices.contains(point.secondImage),
                  let first = replacementIndex(for: oldImages[point.firstImage]),
                  let second = replacementIndex(for: oldImages[point.secondImage])
            else { return nil }
            return DiagnosticControlPoint(
                id: point.id,
                firstImage: first,
                secondImage: second,
                firstX: point.firstX,
                firstY: point.firstY,
                secondX: point.secondX,
                secondY: point.secondY,
                error: point.error
            )
        }
        self.images = images
        modifiedAt = Self.secondPrecision(.now)

        if title == "Namnlöst panorama", let first = images.first {
            title = first.captureDate?.formatted(date: .abbreviated, time: .omitted)
                ?? first.url.deletingPathExtension().lastPathComponent
        }
    }

    mutating func removeImage(at removedIndex: Int) {
        guard images.indices.contains(removedIndex) else { return }
        let remainingControlPoints: [DiagnosticControlPoint]? = controlPoints?.compactMap { point -> DiagnosticControlPoint? in
            guard point.firstImage != removedIndex,
                  point.secondImage != removedIndex else {
                return nil
            }
            return DiagnosticControlPoint(
                id: point.id,
                firstImage: point.firstImage > removedIndex
                    ? point.firstImage - 1 : point.firstImage,
                secondImage: point.secondImage > removedIndex
                    ? point.secondImage - 1 : point.secondImage,
                firstX: point.firstX,
                firstY: point.firstY,
                secondX: point.secondX,
                secondY: point.secondY,
                error: point.error
            )
        }
        images.remove(at: removedIndex)
        controlPoints = remainingControlPoints
        cachedRigImageLines = nil
        cachedRigSignature = nil
        nadirRepairPlacement = nil
        zenithRepairPlacement = nil
        removeUnsupportedControlPoints()
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func setRole(_ role: SourceImage.Role, for imageID: UUID) {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else {
            return
        }
        images[index].role = role
        if role == .fillOnly && images[index].direction == .horizontal {
            images[index].direction = .nadir
        }
        removeUnsupportedControlPoints()
        invalidateRigCache()
        nadirRepairPlacement = nil
        zenithRepairPlacement = nil
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func setRepairArea(
        _ direction: SourceImage.Direction,
        for imageID: UUID
    ) {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else {
            return
        }
        let changesGeometry = images[index].role != .fillOnly
        images[index].role = .fillOnly
        images[index].direction = direction == .horizontal ? .nadir : direction
        removeUnsupportedControlPoints()
        if changesGeometry {
            invalidateRigCache()
        }
        nadirRepairPlacement = nil
        zenithRepairPlacement = nil
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func toggleImageEnabled(_ imageID: UUID) {
        guard let index = images.firstIndex(where: { $0.id == imageID }) else {
            return
        }
        images[index].isEnabled.toggle()
        cachedRigImageLines = nil
        cachedRigSignature = nil
        modifiedAt = Self.secondPrecision(.now)
    }

    var rigSignature: String {
        let imagePart = images
            .filter { $0.role == .alignment }
            .map {
                "\($0.id.uuidString):\($0.isEnabled)"
            }
            .joined(separator: "|")
        return [
            imagePart,
            stitching.engine.rawValue,
            stitching.projection.rawValue,
            stitching.lensProfile.rawValue,
            String(stitching.inputHorizontalFieldOfView)
        ].joined(separator: "#")
    }

    mutating func invalidateRigCache() {
        cachedRigImageLines = nil
        cachedRigSignature = nil
        controlPoints = nil
    }

    mutating func removeUnsupportedControlPoints() {
        for index in images.indices where images[index].role == .fillOnly
            && images[index].direction == .horizontal {
            images[index].direction = .nadir
        }
        controlPoints = controlPoints?.filter { point in
            guard images.indices.contains(point.firstImage),
                  images.indices.contains(point.secondImage) else {
                return false
            }
            let first = images[point.firstImage]
            let second = images[point.secondImage]
            return first.role == .alignment || second.role == .alignment
        }
        if controlPoints?.isEmpty == true {
            controlPoints = nil
        }
        nadirRepairPlacement?.controlPoints = nil
        nadirRepairPlacement?.sphericalProjection = nil
        zenithRepairPlacement?.controlPoints = nil
        zenithRepairPlacement?.sphericalProjection = nil
    }

    mutating func setNadirRepairAdjustment(
        _ adjustment: NadirRepairAdjustment
    ) {
        guard var placement = nadirRepairPlacement else { return }
        placement.manualAdjustment = adjustment.isIdentity ? nil : adjustment
        placement.blendedPreview = false
        nadirRepairPlacement = placement
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func setNadirRepairPreviewBlended(_ isBlended: Bool) {
        guard var placement = nadirRepairPlacement else { return }
        placement.blendedPreview = isBlended
        nadirRepairPlacement = placement
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func setNadirRepairContentBounds(_ bounds: [Double]?) {
        guard var placement = nadirRepairPlacement else { return }
        placement.contentBounds = bounds
        nadirRepairPlacement = placement
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func setZenithRepairAdjustment(
        _ adjustment: NadirRepairAdjustment
    ) {
        guard var placement = zenithRepairPlacement else { return }
        placement.manualAdjustment = adjustment.isIdentity ? nil : adjustment
        placement.blendedPreview = false
        zenithRepairPlacement = placement
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func setZenithRepairPreviewBlended(_ isBlended: Bool) {
        guard var placement = zenithRepairPlacement else { return }
        placement.blendedPreview = isBlended
        zenithRepairPlacement = placement
        modifiedAt = Self.secondPrecision(.now)
    }

    mutating func setZenithRepairContentBounds(_ bounds: [Double]?) {
        guard var placement = zenithRepairPlacement else { return }
        placement.contentBounds = bounds
        zenithRepairPlacement = placement
        modifiedAt = Self.secondPrecision(.now)
    }

    private static func secondPrecision(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

struct StitchingConfiguration: Codable, Equatable, Sendable {
    enum Engine: String, Codable, Sendable {
        case automatic
        case openCV
        case hugin
        case ptGui

        var displayName: String {
            switch self {
            case .automatic: "PanoWizard"
            case .openCV: "OpenCV"
            case .hugin: "Hugin"
            case .ptGui: "PTGui"
            }
        }
    }

    enum Projection: String, Codable, Sendable {
        case automatic
        case cylindrical
        case equirectangular
    }

    enum LensProfile: String, Codable, CaseIterable, Sendable {
        case automatic
        case nikon105DX
        case sigma8DX
        case custom

        var displayName: String {
            switch self {
            case .automatic: "Automatiskt från EXIF"
            case .nikon105DX: "Nikkor 10,5 mm · DX"
            case .sigma8DX: "Sigma 8 mm · DX"
            case .custom: "Eget"
            }
        }

        static let selectableProfiles: [LensProfile] = [
            .sigma8DX,
            .nikon105DX
        ]

        var defaultHorizontalFieldOfView: Double? {
            switch self {
            case .automatic, .custom: nil
            case .nikon105DX: 87.44
            case .sigma8DX: 165.38
            }
        }
    }

    var engine: Engine
    var projection: Projection
    var lensProfile: LensProfile
    var inputHorizontalFieldOfView: Double

    static let automatic = StitchingConfiguration(
        engine: .automatic,
        projection: .automatic,
        lensProfile: .sigma8DX,
        inputHorizontalFieldOfView: 120
    )
}
