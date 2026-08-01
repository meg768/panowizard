import Foundation
import Observation

enum ProjectSelection: Hashable {
    case panorama
    case settings
    case export
    case source(SourceImage.ID)
    case controlPoints
    case poleControlPoints(PanoramaPole)
}

@MainActor
@Observable
final class AppModel {
    enum MaskKind: Hashable {
        case panorama
        case controlPoints
    }

    enum Phase: Equatable {
        case ready
        case importing
        case stitching
        case suggestingControlPoints
        case optimizingControlPoints
        case updatingRepair
        case blendingRepair
        case exporting
        case failed(String)

        var message: String {
            switch self {
            case .ready:
                "Redo"
            case .importing:
                "Läser bilder och metadata…"
            case .stitching:
                "Sammanfogar panorama…"
            case .suggestingControlPoints:
                "Söker kontrollpunkter…"
            case .optimizingControlPoints:
                "Optimerar kontrollpunkter…"
            case .updatingRepair:
                "Uppdaterar nadirreparation…"
            case .blendingRepair:
                "Blandar nadirreparation med Enblend…"
            case .exporting:
                "Skapar interaktiv HTML…"
            case .failed(let message):
                message
            }
        }
    }

    private let importer: any ImageImporting
    private let grouper: any PanoramaGrouping
    private let panoramaEngine: any PanoramaEngine
    private let exporter: any PanoramaExporting

    var project: PanoProject
    var selection: ProjectSelection?
    var phase: Phase = .ready
    var isImporterPresented = false
    var skippedFileCount = 0
    var stitchedResultURL: URL?
    var panoramaViewpoint = PanoramaViewpoint()
    var nadirOverlayURL: URL?
    var zenithOverlayURL: URL?
    var controlPointDiagnostics: ControlPointDiagnostics?
    var editableControlPoints: [DiagnosticControlPoint] = []
    var isSuggestingControlPoints = false
    var selectedControlPointPairID: ControlPointPair.ID?
    var controlPointLeftImageIndex = 0
    var controlPointRightImageIndex = 1
    var maskDataByImageID: [UUID: Data]
    var controlPointMaskDataByImageID: [UUID: Data]
    var maskRevision = 0
    var panoramaRevision = 0
    var brushDiameter: Double = 48
    var isErasingMask = false
    var maskKind: MaskKind = .panorama
    var sourceImageZoom = 1.0
    var isAdjustingNadir = false
    var nadirAdjustment = NadirRepairAdjustment.identity
    var zenithAdjustment = NadirRepairAdjustment.identity
    var activeRepairPole = PanoramaPole.nadir
    var poleControlPointWorkspace: PoleControlPointWorkspace?
    var editablePoleControlPoints: [DiagnosticControlPoint] = []
    private var maskUndoStack: [(MaskKind, UUID, Data?)] = []
    private var repairRenderRevision = 0

    init(
        project: PanoProject,
        importer: any ImageImporting,
        grouper: any PanoramaGrouping,
        panoramaEngine: any PanoramaEngine,
        exporter: any PanoramaExporting,
        masks: [UUID: Data] = [:],
        controlPointMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil,
        zenithOverlayData: Data? = nil
    ) {
        var normalizedProject = project
        if !StitchingConfiguration.LensProfile.selectableProfiles.contains(
            normalizedProject.stitching.lensProfile
        ) {
            normalizedProject.stitching.lensProfile =
                Self.detectedLensProfile(in: project.images) ?? .sigma8DX
        }
        normalizedProject.stitching.inputHorizontalFieldOfView =
            normalizedProject.stitching.lensProfile.defaultHorizontalFieldOfView
                ?? 120
        self.project = normalizedProject
        self.importer = importer
        self.grouper = grouper
        self.panoramaEngine = panoramaEngine
        self.exporter = exporter
        panoramaViewpoint = normalizedProject.previewViewpoint
            ?? PanoramaViewpoint()
        maskDataByImageID = masks
        controlPointMaskDataByImageID = controlPointMasks
        if let savedControlPoints = normalizedProject.controlPoints {
            let ringImages = normalizedProject.images.filter {
                $0.role == .alignment && $0.direction == .horizontal
            }
            editableControlPoints = savedControlPoints
            controlPointDiagnostics = ControlPointDiagnostics(
                images: ringImages,
                rawPoints: savedControlPoints,
                cleanedPoints: savedControlPoints
            )
            selectedControlPointPairID =
                controlPointDiagnostics?.pairs.first?.id
            if let pair = selectedControlPointPairID {
                controlPointLeftImageIndex = pair.firstImage
                controlPointRightImageIndex = pair.secondImage
            }
        }
        nadirAdjustment = project.nadirRepairPlacement?.manualAdjustment
            ?? .identity
        zenithAdjustment = project.zenithRepairPlacement?.manualAdjustment
            ?? .identity
        selection = project.images.first.map { .source($0.id) }
        if let panoramaData {
            stitchedResultURL = Self.restoreData(
                panoramaData,
                filename: "\(project.id.uuidString)-panorama.jpg"
            )
        }
        if let nadirOverlayData {
            nadirOverlayURL = Self.restoreData(
                nadirOverlayData,
                filename: "\(project.id.uuidString)-nadir-overlay.png"
            )
        }
        if let zenithOverlayData {
            zenithOverlayURL = Self.restoreData(
                zenithOverlayData,
                filename: "\(project.id.uuidString)-zenith-overlay.png"
            )
        }
    }

    static func live(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        controlPointMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil,
        zenithOverlayData: Data? = nil
    ) -> AppModel {
        AppModel(
            project: project,
            importer: ImageImportService(metadataReader: ImageMetadataReader()),
            grouper: PanoramaGroupingService(),
            panoramaEngine: HuginOpenCVPanoramaEngine(),
            exporter: FilePanoramaExporter(),
            masks: masks,
            controlPointMasks: controlPointMasks,
            panoramaData: panoramaData,
            nadirOverlayData: nadirOverlayData,
            zenithOverlayData: zenithOverlayData
        )
    }

    var panorama: PanoramaSet? {
        project.images.isEmpty ? nil : project.panorama
    }

    var selectedPreviewURL: URL? {
        switch selection {
        case .panorama:
            return stitchedResultURL ?? project.images.first?.url
        case .source(let id):
            return project.images.first { $0.id == id }?.url
                ?? project.images.first?.url
        case .controlPoints, .poleControlPoints:
            return nil
        case .settings, .export:
            return nil
        case nil:
            return stitchedResultURL ?? project.images.first?.url
        }
    }

    func setPanoramaViewpoint(_ viewpoint: PanoramaViewpoint) {
        guard panoramaViewpoint != viewpoint else { return }
        panoramaViewpoint = viewpoint
        project.previewViewpoint = viewpoint
    }

    var selectedSourceImage: SourceImage? {
        guard case .source(let id) = selection else { return nil }
        return project.images.first { $0.id == id }
    }

    var mainSourceImageID: SourceImage.ID? {
        if case .source(let id) = selection {
            return id
        }
        guard selection == .controlPoints,
              let images = controlPointEditorDiagnostics?.images,
              images.indices.contains(controlPointLeftImageIndex) else {
            return nil
        }
        return images[controlPointLeftImageIndex].id
    }

    var rightSourceImageID: SourceImage.ID? {
        guard selection == .controlPoints,
              let images = controlPointEditorDiagnostics?.images,
              images.indices.contains(controlPointRightImageIndex) else {
            return nil
        }
        return images[controlPointRightImageIndex].id
    }

    var controlPointEditorDiagnostics: ControlPointDiagnostics? {
        let images = controlPointDiagnostics?.images
            ?? project.images.filter {
                $0.role == .alignment && $0.direction == .horizontal
            }
        guard images.count >= 2 else { return nil }
        return ControlPointDiagnostics(
            images: images,
            rawPoints: editableControlPoints,
            cleanedPoints: editableControlPoints
        )
    }

    var isShowingStitchedPanorama: Bool {
        selection == .panorama && stitchedResultURL != nil
    }

    var isShowingNadirRepair: Bool {
        isShowingStitchedPanorama
            && (nadirOverlayURL != nil || zenithOverlayURL != nil)
    }

    var isNadirPreviewBlended: Bool {
        project.nadirRepairPlacement?.isBlendedPreview == true
    }

    var displayedNadirAdjustment: NadirRepairAdjustment {
        activeRepairPole == .zenith
            ? (project.zenithRepairPlacement?.isBlendedPreview == true
                ? .identity : zenithAdjustment)
            : (isNadirPreviewBlended ? .identity : nadirAdjustment)
    }

    var nadirContentBounds: [Double] {
        if activeRepairPole == .zenith {
            return project.zenithRepairPlacement?.resolvedContentBounds
                ?? [0, 0, 1, 1]
        }
        guard
            let bounds = project.nadirRepairPlacement?.contentBounds,
            bounds.count == 4
        else {
            return [0, 0, 1, 1]
        }
        return bounds
    }

    var nadirRepairImage: SourceImage? {
        guard let imageID = project.nadirRepairPlacement?.imageID else {
            return nil
        }
        return project.images.first { $0.id == imageID }
    }

    var hasNadirRepairMask: Bool {
        guard let imageID = project.nadirRepairPlacement?.imageID else {
            return false
        }
        return maskDataByImageID[imageID] != nil
    }

    var canStitch: Bool {
        project.images.filter {
            $0.role == .alignment && $0.direction == .horizontal
        }.count >= 2
            && phase != .importing
            && phase != .stitching
            && phase != .suggestingControlPoints
            && phase != .updatingRepair
            && phase != .blendingRepair
            && phase != .exporting
    }

    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty, phase != .importing else { return }
        phase = .importing

        Task {
            let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            }

            let result = await importer.load(from: urls)
            let uniqueImages = Dictionary(
                (project.images + result.images).map {
                    ($0.url.standardizedFileURL, $0)
                },
                uniquingKeysWith: { current, _ in current }
            ).map(\.value)
            let sortedImages = grouper.group(uniqueImages).flatMap(\.images)

            project.replaceImages(sortedImages)
            if project.stitching.lensProfile == .automatic,
               let detectedProfile = Self.detectedLensProfile(in: sortedImages) {
                project.stitching.lensProfile = detectedProfile
                project.stitching.inputHorizontalFieldOfView =
                    detectedProfile.defaultHorizontalFieldOfView
                    ?? project.stitching.inputHorizontalFieldOfView
            }
            maskDataByImageID = maskDataByImageID.filter { id, _ in
                sortedImages.contains { $0.id == id }
            }
            controlPointMaskDataByImageID =
                controlPointMaskDataByImageID.filter { id, _ in
                    sortedImages.contains { $0.id == id }
                }
            maskRevision += 1
            skippedFileCount += result.skippedFiles
            stitchedResultURL = nil
            nadirOverlayURL = nil
            controlPointDiagnostics = nil
            project.nadirRepairPlacement = nil
            nadirAdjustment = .identity
            isAdjustingNadir = false
            selection = sortedImages.first.map { .source($0.id) }
            phase = .ready
        }
    }

    private static func detectedLensProfile(
        in images: [SourceImage]
    ) -> StitchingConfiguration.LensProfile? {
        let models = images.compactMap(\.lens.model).map { $0.lowercased() }
        if models.contains(where: {
            $0.contains("sigma") && $0.contains("8")
        }) {
            return .sigma8DX
        }
        if models.contains(where: {
            ($0.contains("nikon") || $0.contains("nikkor"))
                && ($0.contains("10.5") || $0.contains("10,5"))
        }) {
            return .nikon105DX
        }
        if images.contains(where: {
            $0.lens.kind == .fisheye
                && ($0.lens.focalLengthIn35mm.map {
                    (11...13).contains($0)
                } ?? false)
        }) {
            return .sigma8DX
        }
        return nil
    }

    func stitch() {
        stitch(
            controlPoints: editableControlPoints.isEmpty
                ? nil
                : editableControlPoints
        )
    }

    func optimizeEditedControlPoints() {
        guard !editableControlPoints.isEmpty, let panorama else { return }
        phase = .optimizingControlPoints
        let points = editableControlPoints
        Task {
            do {
                let result = try await panoramaEngine.optimizeControlPoints(
                    panorama,
                    controlPointMasks: controlPointMaskDataByImageID,
                    controlPoints: points,
                    configuration: project.stitching
                )
                applyControlPointDiagnostics(result.diagnostics)
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func stitch(controlPoints: [DiagnosticControlPoint]?) {
        guard let panorama, canStitch else { return }
        repairRenderRevision += 1
        phase = .stitching
        let previousPlacement = project.nadirRepairPlacement
        let previousZenithPlacement = project.zenithRepairPlacement

        Task {
            do {
                let result = try await panoramaEngine.stitch(
                    panorama,
                    masks: maskDataByImageID,
                    controlPointMasks: controlPointMaskDataByImageID,
                    controlPoints: controlPoints,
                    configuration: project.stitching,
                    cachedRigImageLines: Dictionary(uniqueKeysWithValues:
                        (project.cachedRigSignature == project.rigSignature
                            ? project.cachedRigImageLines ?? [:]
                            : [:]).compactMap {
                            key, value in
                            UUID(uuidString: key).map { ($0, value) }
                        }
                    )
                )
                guard let resultURL = result.url else {
                    throw PanoramaEngineError.stitchingFailed(
                        "Stitchmotorn skapade inget panorama."
                    )
                }
                stitchedResultURL = resultURL
                nadirOverlayURL = result.nadirRepair?.overlayURL
                zenithOverlayURL = result.zenithRepair?.overlayURL
                controlPointDiagnostics = result.controlPointDiagnostics
                if let diagnostics = result.controlPointDiagnostics {
                    applyControlPointDiagnostics(diagnostics)
                }
                var newPlacement = result.nadirRepair?.placement
                if newPlacement?.imageID == previousPlacement?.imageID {
                    newPlacement?.manualAdjustment =
                        previousPlacement?.manualAdjustment
                }
                project.nadirRepairPlacement = newPlacement
                var newZenithPlacement = result.zenithRepair?.placement
                if newZenithPlacement?.imageID
                    == previousZenithPlacement?.imageID {
                    newZenithPlacement?.manualAdjustment =
                        previousZenithPlacement?.manualAdjustment
                }
                project.zenithRepairPlacement = newZenithPlacement
                nadirAdjustment = newPlacement?.manualAdjustment ?? .identity
                zenithAdjustment = newZenithPlacement?.manualAdjustment
                    ?? .identity
                isAdjustingNadir = false
                if !result.rigImageLines.isEmpty {
                    project.cachedRigImageLines = Dictionary(uniqueKeysWithValues:
                        result.rigImageLines.map { ($0.key.uuidString, $0.value) }
                    )
                    project.cachedRigSignature = project.rigSignature
                }
                panoramaRevision += 1
                selection = .panorama
                phase = .ready
                if result.nadirRepair != nil {
                    renderBlendedRepairPreview(.nadir)
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func applyControlPointDiagnostics(
        _ diagnostics: ControlPointDiagnostics
    ) {
        controlPointDiagnostics = diagnostics
        editableControlPoints = diagnostics.cleanedPoints
        project.controlPoints = diagnostics.cleanedPoints
        selectedControlPointPairID =
            selectedControlPointPairID.flatMap { selected in
                diagnostics.pairs.contains { $0.id == selected }
                    ? selected
                    : nil
            } ?? diagnostics.pairs.first?.id
        if let pair = selectedControlPointPairID {
            controlPointLeftImageIndex = pair.firstImage
            controlPointRightImageIndex = pair.secondImage
        }
    }

    func moveControlPoint(
        _ id: DiagnosticControlPoint.ID,
        in imageIndex: Int,
        to point: CGPoint
    ) {
        guard let index = editableControlPoints.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }
        if editableControlPoints[index].firstImage == imageIndex {
            editableControlPoints[index].firstX = point.x
            editableControlPoints[index].firstY = point.y
        } else if editableControlPoints[index].secondImage == imageIndex {
            editableControlPoints[index].secondX = point.x
            editableControlPoints[index].secondY = point.y
        }
        editableControlPoints[index].error = nil
        project.controlPoints = editableControlPoints
        project.modifiedAt = Date(
            timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)
        )
    }

    func removeControlPoint(_ id: DiagnosticControlPoint.ID) {
        editableControlPoints.removeAll { $0.id == id }
        saveEditableControlPoints()
    }

    func removeAllControlPoints(in pair: ControlPointPair.ID) {
        editableControlPoints.removeAll { $0.pair == pair }
        saveEditableControlPoints()
    }

    func removeAllControlPoints() {
        editableControlPoints = []
        saveEditableControlPoints()
    }

    func suggestControlPoints(for pair: ControlPointPair.ID) {
        guard !isSuggestingControlPoints,
              let images = controlPointEditorDiagnostics?.images else {
            return
        }
        isSuggestingControlPoints = true
        phase = .suggestingControlPoints
        let horizontalFieldOfView = project.stitching.inputHorizontalFieldOfView
        let existingPoints = editableControlPoints
        let controlPointMasks = controlPointMaskDataByImageID

        Task {
            do {
                let matches = try await Task.detached(priority: .userInitiated) {
                    try OpenCVControlPointMatcher.pair(
                        images: images,
                        pair: pair,
                        horizontalFieldOfView: horizontalFieldOfView,
                        controlPointMasks: controlPointMasks
                    )
                }.value
                let firstImage = images[pair.firstImage]
                let secondImage = images[pair.secondImage]
                let firstMask = SourceMaskRasterizer.exclusionMap(
                    from: controlPointMasks[firstImage.id],
                    width: firstImage.pixelWidth,
                    height: firstImage.pixelHeight
                )
                let secondMask = SourceMaskRasterizer.exclusionMap(
                    from: controlPointMasks[secondImage.id],
                    width: secondImage.pixelWidth,
                    height: secondImage.pixelHeight
                )
                let candidates = matches
                    .map {
                        DiagnosticControlPoint(
                            firstImage: $0.firstImage,
                            secondImage: $0.secondImage,
                            firstX: $0.firstX,
                            firstY: $0.firstY,
                            secondX: $0.secondX,
                            secondY: $0.secondY
                        )
                    }
                    .filter { candidate in
                        let isMasked =
                            firstMask?.contains(CGPoint(
                                x: candidate.firstX,
                                y: candidate.firstY
                            )) == true
                            || secondMask?.contains(CGPoint(
                                x: candidate.secondX,
                                y: candidate.secondY
                            )) == true
                        return !isMasked && !existingPoints.contains {
                            $0.pair == candidate.pair
                                && (
                                    hypot(
                                        $0.firstX - candidate.firstX,
                                        $0.firstY - candidate.firstY
                                    ) < 30
                                        || hypot(
                                            $0.secondX - candidate.secondX,
                                            $0.secondY - candidate.secondY
                                        ) < 30
                                )
                        }
                    }
                let suggestions = spatiallyDistributedControlPoints(
                    from: candidates,
                    existing: existingPoints.filter { $0.pair == pair },
                    images: images,
                    maximumCount: 10
                )
                editableControlPoints.append(contentsOf: suggestions)
                saveEditableControlPoints()
                isSuggestingControlPoints = false
                phase = .ready
            } catch {
                isSuggestingControlPoints = false
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func suggestControlPointsForProject() {
        suggestControlPointsForProject(replacingExisting: false)
    }

    func regenerateControlPointsForProject() {
        suggestControlPointsForProject(replacingExisting: true)
    }

    private func suggestControlPointsForProject(replacingExisting: Bool) {
        guard !isSuggestingControlPoints,
              let images = controlPointEditorDiagnostics?.images else {
            return
        }
        isSuggestingControlPoints = true
        phase = .suggestingControlPoints
        let horizontalFieldOfView = project.stitching.inputHorizontalFieldOfView
        let existingPoints = replacingExisting ? [] : editableControlPoints
        let controlPointMasks = controlPointMaskDataByImageID

        Task {
            do {
                let matches = try await Task.detached(priority: .userInitiated) {
                    try OpenCVControlPointMatcher.ring(
                        images: images,
                        horizontalFieldOfView: horizontalFieldOfView,
                        controlPointMasks: controlPointMasks
                    )
                }.value
                let exclusionMaps = Dictionary(
                    uniqueKeysWithValues: images.enumerated().compactMap {
                        index,
                        image in
                        SourceMaskRasterizer.exclusionMap(
                            from: controlPointMasks[image.id],
                            width: image.pixelWidth,
                            height: image.pixelHeight
                        ).map { (index, $0) }
                    }
                )
                let mappedPoints: [DiagnosticControlPoint] = matches.map {
                    DiagnosticControlPoint(
                        firstImage: $0.firstImage,
                        secondImage: $0.secondImage,
                        firstX: $0.firstX,
                        firstY: $0.firstY,
                        secondX: $0.secondX,
                        secondY: $0.secondY
                    )
                }
                let candidates = mappedPoints.filter { candidate in
                    let firstIsMasked =
                        exclusionMaps[candidate.firstImage]?.contains(CGPoint(
                        x: candidate.firstX,
                        y: candidate.firstY
                    )) == true
                    let secondIsMasked =
                        exclusionMaps[candidate.secondImage]?.contains(CGPoint(
                            x: candidate.secondX,
                            y: candidate.secondY
                        )) == true
                    let duplicatesExisting = existingPoints.contains { point in
                        guard point.pair == candidate.pair else { return false }
                        let firstDistance = hypot(
                            point.firstX - candidate.firstX,
                            point.firstY - candidate.firstY
                        )
                        let secondDistance = hypot(
                            point.secondX - candidate.secondX,
                            point.secondY - candidate.secondY
                        )
                        return firstDistance < 30 || secondDistance < 30
                    }
                    return !firstIsMasked
                        && !secondIsMasked
                        && !duplicatesExisting
                }
                let groupedCandidates = Dictionary(
                    grouping: candidates,
                    by: \.pair
                )
                let suggestions = groupedCandidates.keys.sorted()
                    .flatMap { pair in
                        spatiallyDistributedControlPoints(
                            from: groupedCandidates[pair, default: []],
                            existing: existingPoints.filter { $0.pair == pair },
                            images: images,
                            maximumCount: 10
                        )
                    }
                if replacingExisting {
                    editableControlPoints = suggestions
                } else {
                    editableControlPoints.append(contentsOf: suggestions)
                }
                saveEditableControlPoints()
                isSuggestingControlPoints = false
                phase = .ready
            } catch {
                isSuggestingControlPoints = false
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func spatiallyDistributedControlPoints(
        from candidates: [DiagnosticControlPoint],
        existing: [DiagnosticControlPoint],
        images: [SourceImage],
        maximumCount: Int
    ) -> [DiagnosticControlPoint] {
        guard maximumCount > 0, !candidates.isEmpty else { return [] }
        var remaining = candidates
        var selected: [DiagnosticControlPoint] = []

        while selected.count < maximumCount, !remaining.isEmpty {
            let anchors = existing + selected
            let nextIndex: Int
            if anchors.isEmpty {
                nextIndex = 0
            } else {
                nextIndex = remaining.indices.max { left, right in
                    minimumNormalizedDistance(
                        from: remaining[left],
                        to: anchors,
                        images: images
                    ) < minimumNormalizedDistance(
                        from: remaining[right],
                        to: anchors,
                        images: images
                    )
                } ?? 0
            }
            selected.append(remaining.remove(at: nextIndex))
        }
        return selected
    }

    private func minimumNormalizedDistance(
        from candidate: DiagnosticControlPoint,
        to anchors: [DiagnosticControlPoint],
        images: [SourceImage]
    ) -> Double {
        guard images.indices.contains(candidate.firstImage),
              images.indices.contains(candidate.secondImage) else {
            return 0
        }
        let firstImage = images[candidate.firstImage]
        let secondImage = images[candidate.secondImage]
        return anchors.map { anchor in
            let firstDistance = hypot(
                (candidate.firstX - anchor.firstX)
                    / Double(max(firstImage.pixelWidth, 1)),
                (candidate.firstY - anchor.firstY)
                    / Double(max(firstImage.pixelHeight, 1))
            )
            let secondDistance = hypot(
                (candidate.secondX - anchor.secondX)
                    / Double(max(secondImage.pixelWidth, 1)),
                (candidate.secondY - anchor.secondY)
                    / Double(max(secondImage.pixelHeight, 1))
            )
            return min(firstDistance, secondDistance)
        }
        .min() ?? .greatestFiniteMagnitude
    }

    func selectControlPointImages(_ first: Int, _ second: Int) {
        guard first != second else { return }
        controlPointLeftImageIndex = first
        controlPointRightImageIndex = second
        selectedControlPointPairID = ControlPointPair.ID(
            firstImage: min(first, second),
            secondImage: max(first, second)
        )
    }

    func selectSourceImage(_ id: SourceImage.ID, asRightImage: Bool) {
        guard project.images.contains(where: { $0.id == id }) else { return }
        guard asRightImage else {
            selection = .source(id)
            return
        }
        guard let mainID = mainSourceImageID,
              mainID != id,
              let images = controlPointEditorDiagnostics?.images,
              let mainIndex = images.firstIndex(where: { $0.id == mainID }),
              let rightIndex = images.firstIndex(where: { $0.id == id }) else {
            return
        }
        selectControlPointImages(mainIndex, rightIndex)
        selection = .controlPoints
    }

    @discardableResult
    func addPredictedControlPoint(
        to pair: ControlPointPair.ID,
        point: CGPoint,
        in imageIndex: Int
    ) -> DiagnosticControlPoint.ID {
        let clickedFirstImage = imageIndex == pair.firstImage
        let firstPoint = clickedFirstImage
            ? point
            : predictedCounterpart(
                for: point,
                in: pair,
                clickedFirstImage: false
            )
        let secondPoint = clickedFirstImage
            ? predictedCounterpart(
                for: point,
                in: pair,
                clickedFirstImage: true
            )
            : point
        let point = DiagnosticControlPoint(
            firstImage: pair.firstImage,
            secondImage: pair.secondImage,
            firstX: firstPoint.x,
            firstY: firstPoint.y,
            secondX: secondPoint.x,
            secondY: secondPoint.y
        )
        editableControlPoints.append(point)
        saveEditableControlPoints()
        return point.id
    }

    private func predictedCounterpart(
        for clickedPoint: CGPoint,
        in pair: ControlPointPair.ID,
        clickedFirstImage: Bool
    ) -> CGPoint {
        let candidates = editableControlPoints
            .filter { $0.pair == pair }
            .map { point -> (DiagnosticControlPoint, Double) in
                let distance = hypot(
                    (clickedFirstImage ? point.firstX : point.secondX)
                        - clickedPoint.x,
                    (clickedFirstImage ? point.firstY : point.secondY)
                        - clickedPoint.y
                )
                return (point, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(12)
        guard !candidates.isEmpty else { return clickedPoint }

        if candidates.count >= 3 {
            let samples = candidates.map { point, distance in
                let source = clickedFirstImage
                    ? CGPoint(x: point.firstX, y: point.firstY)
                    : CGPoint(x: point.secondX, y: point.secondY)
                let destination = clickedFirstImage
                    ? CGPoint(x: point.secondX, y: point.secondY)
                    : CGPoint(x: point.firstX, y: point.firstY)
                let weight = 1.0 / pow(max(distance, 80), 2)
                return (source, destination, weight)
            }
            if let predicted = locallyAffinePrediction(
                at: clickedPoint,
                samples: samples
            ) {
                return clampedCounterpart(
                    predicted,
                    for: pair,
                    clickedFirstImage: clickedFirstImage
                )
            }
        }

        var totalWeight = 0.0
        var predictedX = 0.0
        var predictedY = 0.0
        for (point, distance) in candidates {
            let weight = 1.0 / max(distance, 24)
            let offsetX = clickedFirstImage
                ? point.secondX - point.firstX
                : point.firstX - point.secondX
            let offsetY = clickedFirstImage
                ? point.secondY - point.firstY
                : point.firstY - point.secondY
            predictedX += (clickedPoint.x + offsetX) * weight
            predictedY += (clickedPoint.y + offsetY) * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return clickedPoint }
        return clampedCounterpart(
            CGPoint(x: predictedX / totalWeight, y: predictedY / totalWeight),
            for: pair,
            clickedFirstImage: clickedFirstImage
        )
    }

    private func locallyAffinePrediction(
        at point: CGPoint,
        samples: [(source: CGPoint, destination: CGPoint, weight: Double)]
    ) -> CGPoint? {
        var normal = Array(
            repeating: Array(repeating: 0.0, count: 3),
            count: 3
        )
        var targetX = Array(repeating: 0.0, count: 3)
        var targetY = Array(repeating: 0.0, count: 3)
        for sample in samples {
            let row = [Double(sample.source.x), Double(sample.source.y), 1]
            for i in 0..<3 {
                targetX[i] += sample.weight * row[i]
                    * Double(sample.destination.x)
                targetY[i] += sample.weight * row[i]
                    * Double(sample.destination.y)
                for j in 0..<3 {
                    normal[i][j] += sample.weight * row[i] * row[j]
                }
            }
        }
        guard let coefficientsX = solve3x3(normal, targetX),
              let coefficientsY = solve3x3(normal, targetY) else {
            return nil
        }
        let row = [Double(point.x), Double(point.y), 1]
        return CGPoint(
            x: zip(coefficientsX, row).map(*).reduce(0, +),
            y: zip(coefficientsY, row).map(*).reduce(0, +)
        )
    }

    private func solve3x3(
        _ matrix: [[Double]],
        _ target: [Double]
    ) -> [Double]? {
        var augmented = zip(matrix, target).map { $0 + [$1] }
        for column in 0..<3 {
            guard let pivot = (column..<3).max(by: {
                abs(augmented[$0][column]) < abs(augmented[$1][column])
            }), abs(augmented[pivot][column]) > 1e-10 else {
                return nil
            }
            augmented.swapAt(column, pivot)
            let divisor = augmented[column][column]
            for index in column..<4 {
                augmented[column][index] /= divisor
            }
            for row in 0..<3 where row != column {
                let factor = augmented[row][column]
                for index in column..<4 {
                    augmented[row][index] -= factor * augmented[column][index]
                }
            }
        }
        return augmented.map { $0[3] }
    }

    private func clampedCounterpart(
        _ point: CGPoint,
        for pair: ControlPointPair.ID,
        clickedFirstImage: Bool
    ) -> CGPoint {
        let images = controlPointDiagnostics?.images ?? []
        let index = clickedFirstImage ? pair.secondImage : pair.firstImage
        let image = images.indices.contains(index) ? images[index] : nil
        return CGPoint(
            x: min(max(point.x, 0), image.map {
                Double($0.pixelWidth)
            } ?? .greatestFiniteMagnitude),
            y: min(max(point.y, 0), image.map {
                Double($0.pixelHeight)
            } ?? .greatestFiniteMagnitude)
        )
    }

    private func saveEditableControlPoints() {
        project.controlPoints = editableControlPoints
        project.modifiedAt = Date(
            timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)
        )
    }

    func removeSelectedSourceImage() {
        guard case .source(let id) = selection,
              let index = project.images.firstIndex(where: { $0.id == id }) else {
            return
        }

        var images = project.images
        images.remove(at: index)
        project.replaceImages(images)
        maskDataByImageID[id] = nil
        controlPointMaskDataByImageID[id] = nil
        maskRevision += 1
        repairRenderRevision += 1
        stitchedResultURL = nil
        nadirOverlayURL = nil
        controlPointDiagnostics = nil
        project.nadirRepairPlacement = nil
        nadirAdjustment = .identity
        isAdjustingNadir = false

        if images.isEmpty {
            selection = nil
        } else {
            selection = .source(images[min(index, images.count - 1)].id)
        }
    }

    func setRole(_ role: SourceImage.Role, for imageID: UUID) {
        repairRenderRevision += 1
        project.setRole(role, for: imageID)
        stitchedResultURL = nil
        nadirOverlayURL = nil
        nadirAdjustment = .identity
        isAdjustingNadir = false
        panoramaRevision += 1
    }

    func setDirection(_ direction: SourceImage.Direction, for imageID: UUID) {
        repairRenderRevision += 1
        project.setDirection(direction, for: imageID)
        stitchedResultURL = nil
        nadirOverlayURL = nil
        nadirAdjustment = .identity
        isAdjustingNadir = false
        panoramaRevision += 1
    }

    func updateStitchingConfiguration(
        _ update: (inout StitchingConfiguration) -> Void
    ) {
        repairRenderRevision += 1
        let previous = project.stitching
        update(&project.stitching)
        if project.stitching != previous {
            project.invalidateRigCache()
        }
        stitchedResultURL = nil
        nadirOverlayURL = nil
        project.nadirRepairPlacement = nil
        nadirAdjustment = .identity
        isAdjustingNadir = false
        panoramaRevision += 1
    }

    func maskData(for id: UUID) -> Data? {
        activeMaskKind == .controlPoints
            ? controlPointMaskDataByImageID[id]
            : maskDataByImageID[id]
    }

    func setMaskData(_ data: Data?, for id: UUID) {
        let kind = activeMaskKind
        if kind == .controlPoints {
            maskUndoStack.append((kind, id, controlPointMaskDataByImageID[id]))
            controlPointMaskDataByImageID[id] = data
        } else {
            maskUndoStack.append((kind, id, maskDataByImageID[id]))
            maskDataByImageID[id] = data
        }
        maskRevision += 1
        if kind == .controlPoints {
            project.invalidateRigCache()
            stitchedResultURL = nil
            nadirOverlayURL = nil
            project.nadirRepairPlacement = nil
            nadirAdjustment = .identity
            isAdjustingNadir = false
            panoramaRevision += 1
            return
        }
        if refreshRepairOverlayIfPossible(for: id) {
            return
        }
        repairRenderRevision += 1
        stitchedResultURL = nil
        nadirOverlayURL = nil
        project.nadirRepairPlacement = nil
        nadirAdjustment = .identity
        isAdjustingNadir = false
        panoramaRevision += 1
    }

    func clearSelectedMask() {
        guard
            let image = selectedSourceImage,
            maskData(for: image.id) != nil
        else {
            return
        }
        setMaskData(nil, for: image.id)
    }

    func invertSelectedMask() {
        guard let image = selectedSourceImage,
              let currentData = maskData(for: image.id),
              let invertedData = SourceMaskRasterizer.inverted(
                  currentData,
                  width: image.pixelWidth,
                  height: image.pixelHeight,
                  controlPointExclusion: activeMaskKind == .controlPoints
              ) else {
            return
        }
        setMaskData(invertedData, for: image.id)
    }

    var canUndoMask: Bool {
        !maskUndoStack.isEmpty
    }

    func undoMask() {
        guard let (kind, id, data) = maskUndoStack.popLast() else { return }
        if kind == .controlPoints {
            controlPointMaskDataByImageID[id] = data
        } else {
            maskDataByImageID[id] = data
        }
        maskRevision += 1
        if kind == .controlPoints {
            project.invalidateRigCache()
            stitchedResultURL = nil
            nadirOverlayURL = nil
            project.nadirRepairPlacement = nil
            nadirAdjustment = .identity
            isAdjustingNadir = false
            panoramaRevision += 1
            return
        }
        if refreshRepairOverlayIfPossible(for: id) {
            return
        }
        repairRenderRevision += 1
        stitchedResultURL = nil
        nadirOverlayURL = nil
        project.nadirRepairPlacement = nil
        nadirAdjustment = .identity
        isAdjustingNadir = false
        panoramaRevision += 1
    }

    var activeMaskKind: MaskKind {
        selectedSourceImage?.role == .fillOnly ? .panorama : maskKind
    }

    func zoomSourceImageIn() {
        sourceImageZoom = min(sourceImageZoom * 1.25, 8)
    }

    func zoomSourceImageOut() {
        sourceImageZoom = max(sourceImageZoom / 1.25, 1)
    }

    func setNadirAdjustment(_ adjustment: NadirRepairAdjustment) {
        if activeRepairPole == .zenith {
            zenithAdjustment = adjustment
            project.setZenithRepairAdjustment(adjustment)
            return
        }
        nadirAdjustment = adjustment
        project.setNadirRepairAdjustment(adjustment)
    }

    func resetNadirAdjustment() {
        setNadirAdjustment(.identity)
    }

    func beginRepairAdjustment(_ pole: PanoramaPole) {
        guard phase == .ready else { return }
        let available = pole == .zenith
            ? zenithOverlayURL != nil
            : nadirOverlayURL != nil
        guard available else { return }
        activeRepairPole = pole
        let placement = pole == .zenith
            ? project.zenithRepairPlacement
            : project.nadirRepairPlacement
        if placement?.isBlendedPreview == true,
           let imageID = placement?.imageID {
            _ = refreshRepairOverlayIfPossible(
                for: imageID,
                enterAdjustment: true
            )
            return
        }
        selection = .panorama
        isAdjustingNadir = true
    }

    func toggleNadirAdjustment() {
        if activeRepairPole == .zenith {
            if isAdjustingNadir {
                renderBlendedRepairPreview(.zenith)
            } else {
                isAdjustingNadir = true
            }
            return
        }
        guard phase == .ready,
              let placement = project.nadirRepairPlacement else {
            return
        }
        if isAdjustingNadir {
            renderBlendedRepairPreview(.nadir)
        } else if placement.isBlendedPreview {
            _ = refreshRepairOverlayIfPossible(
                for: placement.imageID,
                enterAdjustment: true
            )
        } else {
            isAdjustingNadir = true
        }
    }

    func showNadirRepairPreview() {
        guard phase == .ready else { return }
        renderBlendedRepairPreview(.nadir)
    }

    var canExportHTML: Bool {
        stitchedResultURL != nil
            && phase == .ready
            && (
                project.nadirRepairPlacement == nil
                    || project.nadirRepairPlacement?.isBlendedPreview == true
            )
            && (
                project.zenithRepairPlacement == nil
                    || project.zenithRepairPlacement?.isBlendedPreview == true
            )
    }

    func exportHTML(
        to destinationURL: URL,
        initialViewpoint: PanoramaViewpoint
    ) {
        guard let panoramaURL = stitchedResultURL, canExportHTML else { return }
        phase = .exporting
        Task {
            do {
                try await exporter.exportHTML(
                    panoramaURL: panoramaURL,
                    nadirOverlayURL: project.nadirRepairPlacement == nil
                        ? nil
                        : nadirOverlayURL,
                    zenithOverlayURL: project.zenithRepairPlacement == nil
                        ? nil
                        : zenithOverlayURL,
                    title: project.title,
                    initialViewpoint: initialViewpoint,
                    to: destinationURL
                )
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func interactiveHTMLArchiveForSharing(
        initialViewpoint: PanoramaViewpoint
    ) async throws -> URL {
        guard let panoramaURL = stitchedResultURL, canExportHTML else {
            throw PanoramaEngineError.stitchingFailed(
                "Panoramat är inte färdigt för export."
            )
        }
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/Exports",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let safeTitle = project.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let destinationURL = directory.appending(
            path: "\(safeTitle)-\(UUID().uuidString.prefix(8)).html"
        )
        phase = .exporting
        do {
            try await exporter.exportHTML(
                panoramaURL: panoramaURL,
                nadirOverlayURL: project.nadirRepairPlacement == nil
                    ? nil
                    : nadirOverlayURL,
                zenithOverlayURL: project.zenithRepairPlacement == nil
                    ? nil
                    : zenithOverlayURL,
                title: project.title,
                initialViewpoint: initialViewpoint,
                to: destinationURL
            )
            let archiveURL = directory.appending(
                path: "\(safeTitle)-\(UUID().uuidString.prefix(8)).zip"
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-c", "-k", "--sequesterRsrc", "--keepParent",
                destinationURL.path(percentEncoded: false),
                archiveURL.path(percentEncoded: false)
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: archiveURL.path)
            else {
                throw PanoramaEngineError.stitchingFailed(
                    "HTML-filen kunde inte packas för delning."
                )
            }
            phase = .ready
            return archiveURL
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    func selectNadirRepairForMasking() {
        guard let imageID = project.nadirRepairPlacement?.imageID else {
            return
        }
        isAdjustingNadir = false
        selection = .source(imageID)
    }

    var panoramaData: Data? {
        guard let stitchedResultURL else { return nil }
        return try? Data(contentsOf: stitchedResultURL)
    }

    var nadirOverlayData: Data? {
        guard let nadirOverlayURL else { return nil }
        return try? Data(contentsOf: nadirOverlayURL)
    }

    var zenithOverlayData: Data? {
        guard let zenithOverlayURL else { return nil }
        return try? Data(contentsOf: zenithOverlayURL)
    }

    private static func restoreData(_ data: Data, filename: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PanoWizard/Projects", directoryHint: .isDirectory)
        let url = directory.appending(path: filename)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }


    private func refreshRepairOverlayIfPossible(
        for imageID: UUID,
        enterAdjustment: Bool = false
    ) -> Bool {
        guard
            let repairImage = project.images.first(where: {
                $0.id == imageID
                    && $0.role == .fillOnly
                    && $0.direction != .horizontal
            }),
            let placement = repairImage.direction == .zenith
                ? project.zenithRepairPlacement
                : project.nadirRepairPlacement,
            placement.imageID == imageID,
            stitchedResultURL != nil
        else {
            return false
        }

        repairRenderRevision += 1
        let revision = repairRenderRevision
        let exclusionMaskData = maskDataByImageID[imageID]
        let horizontalFieldOfView =
            project.stitching.inputHorizontalFieldOfView
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/Repairs/\(project.id.uuidString)",
                directoryHint: .isDirectory
            )
        let outputURL = outputDirectory.appending(
            path: "\(UUID().uuidString)-\(repairImage.direction.rawValue)-overlay.png"
        )
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            phase = .failed(error.localizedDescription)
            return true
        }

        phase = .updatingRepair
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try OpenCVNadirRepairRegistrar.renderOverlay(
                        repairImage: repairImage,
                        exclusionMaskData: exclusionMaskData,
                        horizontalFieldOfView: horizontalFieldOfView,
                        placement: placement,
                        outputURL: outputURL
                    )
                }.value
                guard revision == repairRenderRevision else { return }
                let bounds = OpenCVNadirRepairRegistrar.alphaContentBounds(
                    at: outputURL
                )
                if repairImage.direction == .zenith {
                    zenithOverlayURL = outputURL
                    project.setZenithRepairContentBounds(bounds)
                    project.setZenithRepairPreviewBlended(false)
                } else {
                    nadirOverlayURL = outputURL
                    project.setNadirRepairContentBounds(bounds)
                    project.setNadirRepairPreviewBlended(false)
                }
                if enterAdjustment {
                    activeRepairPole = repairImage.direction == .zenith
                        ? .zenith : .nadir
                    selection = .panorama
                    isAdjustingNadir = true
                }
                panoramaRevision += 1
                phase = .ready
            } catch {
                guard revision == repairRenderRevision else { return }
                phase = .failed(error.localizedDescription)
            }
        }
        return true
    }

    private func renderBlendedRepairPreview(_ pole: PanoramaPole) {
        guard
            let panoramaURL = stitchedResultURL,
            let placement = pole == .zenith
                ? project.zenithRepairPlacement
                : project.nadirRepairPlacement,
            let repairImage = project.images.first(where: {
                $0.id == placement.imageID
                    && $0.role == .fillOnly
                    && $0.direction == (pole == .zenith ? .zenith : .nadir)
            })
        else {
            return
        }

        repairRenderRevision += 1
        let revision = repairRenderRevision
        let exclusionMaskData = maskDataByImageID[repairImage.id]
        let horizontalFieldOfView =
            project.stitching.inputHorizontalFieldOfView
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/Repairs/\(project.id.uuidString)",
                directoryHint: .isDirectory
            )
        let outputURL = outputDirectory.appending(
            path: "\(UUID().uuidString)-\(pole.rawValue)-blended.png"
        )
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        isAdjustingNadir = false
        phase = .blendingRepair
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try OpenCVNadirRepairRegistrar.renderBlendedOverlay(
                        panoramaURL: panoramaURL,
                        repairImage: repairImage,
                        exclusionMaskData: exclusionMaskData,
                        horizontalFieldOfView: horizontalFieldOfView,
                        pole: pole,
                        placement: placement,
                        outputURL: outputURL
                    )
                }.value
                guard revision == repairRenderRevision else { return }
                if pole == .zenith {
                    zenithOverlayURL = outputURL
                    project.setZenithRepairPreviewBlended(true)
                } else {
                    nadirOverlayURL = outputURL
                    project.setNadirRepairPreviewBlended(true)
                }
                selection = .panorama
                panoramaRevision += 1
                phase = .ready
            } catch {
                guard revision == repairRenderRevision else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    var poleControlPointDiagnostics: ControlPointDiagnostics? {
        guard let workspace = poleControlPointWorkspace else { return nil }
        let lens = LensDescription(
            model: "Lokal 120°-vy",
            focalLengthIn35mm: nil,
            kind: .rectilinear
        )
        let images = [
            SourceImage(
                url: workspace.repairViewURL,
                captureDate: nil,
                pixelWidth: 1_600,
                pixelHeight: 1_600,
                cameraModel: nil,
                lens: lens
            ),
            SourceImage(
                url: workspace.ringViewURL,
                captureDate: nil,
                pixelWidth: 1_600,
                pixelHeight: 1_600,
                cameraModel: nil,
                lens: lens
            )
        ]
        return ControlPointDiagnostics(
            images: images,
            rawPoints: editablePoleControlPoints,
            cleanedPoints: editablePoleControlPoints
        )
    }

    func beginPoleControlPointAlignment(_ pole: PanoramaPole) {
        guard let panoramaURL = stitchedResultURL,
              let placement = pole == .zenith
                ? project.zenithRepairPlacement
                : project.nadirRepairPlacement,
              let image = project.images.first(where: { $0.id == placement.imageID })
        else { return }
        phase = .suggestingControlPoints
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/PoleCP/\(project.id.uuidString)/\(pole.rawValue)",
            directoryHint: .isDirectory
        )
        let horizontalFieldOfView = project.stitching.inputHorizontalFieldOfView
        Task {
            do {
                let workspace = try await Task.detached(priority: .userInitiated) {
                    try OpenCVNadirRepairRegistrar.controlPointWorkspace(
                        panoramaURL: panoramaURL,
                        repairImage: image,
                        horizontalFieldOfView: horizontalFieldOfView,
                        pole: pole,
                        directory: directory
                    )
                }.value
                poleControlPointWorkspace = workspace
                editablePoleControlPoints = placement.controlPoints?.isEmpty == false
                    ? placement.controlPoints!
                    : workspace.points
                activeRepairPole = pole
                selection = .poleControlPoints(pole)
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func regeneratePoleControlPoints() {
        if activeRepairPole == .zenith {
            project.zenithRepairPlacement?.controlPoints = nil
        } else {
            project.nadirRepairPlacement?.controlPoints = nil
        }
        beginPoleControlPointAlignment(activeRepairPole)
    }

    func movePoleControlPoint(
        _ id: DiagnosticControlPoint.ID,
        imageIndex: Int,
        point: CGPoint
    ) {
        guard let index = editablePoleControlPoints.firstIndex(where: { $0.id == id })
        else { return }
        if imageIndex == 0 {
            editablePoleControlPoints[index].firstX = point.x
            editablePoleControlPoints[index].firstY = point.y
        } else {
            editablePoleControlPoints[index].secondX = point.x
            editablePoleControlPoints[index].secondY = point.y
        }
        editablePoleControlPoints[index].error = nil
    }

    func removePoleControlPoint(_ id: DiagnosticControlPoint.ID) {
        editablePoleControlPoints.removeAll { $0.id == id }
    }

    @discardableResult
    func addPoleControlPoint(point: CGPoint, imageIndex: Int) -> UUID {
        let counterpart = predictedPoleCounterpart(point, from: imageIndex)
        let value = DiagnosticControlPoint(
            firstImage: 0,
            secondImage: 1,
            firstX: imageIndex == 0 ? point.x : counterpart.x,
            firstY: imageIndex == 0 ? point.y : counterpart.y,
            secondX: imageIndex == 1 ? point.x : counterpart.x,
            secondY: imageIndex == 1 ? point.y : counterpart.y
        )
        editablePoleControlPoints.append(value)
        return value.id
    }

    private func predictedPoleCounterpart(
        _ point: CGPoint,
        from imageIndex: Int
    ) -> CGPoint {
        guard let placement = activeRepairPole == .zenith
            ? project.zenithRepairPlacement : project.nadirRepairPlacement,
              placement.localHomography.count == 9 else { return point }
        let h = placement.localHomography
        if imageIndex == 0 {
            let w = h[6] * point.x + h[7] * point.y + h[8]
            return CGPoint(
                x: (h[0] * point.x + h[1] * point.y + h[2]) / w,
                y: (h[3] * point.x + h[4] * point.y + h[5]) / w
            )
        }
        return point
    }

    func applyPoleControlPoints() {
        guard editablePoleControlPoints.count >= 4,
              let placement = activeRepairPole == .zenith
                ? project.zenithRepairPlacement : project.nadirRepairPlacement
        else { return }
        phase = .optimizingControlPoints
        do {
            let result = try OpenCVNadirRepairRegistrar.placement(
                bySolving: editablePoleControlPoints,
                from: placement
            )
            editablePoleControlPoints = result.1
            if activeRepairPole == .zenith {
                project.zenithRepairPlacement = result.0
                zenithAdjustment = .identity
            } else {
                project.nadirRepairPlacement = result.0
                nadirAdjustment = .identity
            }
            phase = .ready
            _ = refreshRepairOverlayIfPossible(
                for: result.0.imageID,
                enterAdjustment: true
            )
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
