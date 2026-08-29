import Foundation
import ImageIO
import Observation

enum ProjectSelection: Hashable {
    case panorama
    case settings
    case retouch
    case export
    case source(SourceImage.ID)
    case controlPoints
}

@MainActor
@Observable
final class AppModel {
    static let suggestedControlPointBatchSize = 10

    enum SourceMaskIntent: Hashable {
        case exclude
        case protect
        case erase
    }
    enum MaskKind: Hashable {
        case panorama
        case protected
    }

    enum Phase: Equatable {
        case ready
        case importing
        case stitching
        case suggestingControlPoints
        case optimizingControlPoints
        case updatingRepair
        case blendingRepair
        case retouching
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
            case .retouching:
                "Retuscherar polbild…"
            case .exporting:
                "Exporterar…"
            case .failed(let message):
                message
            }
        }

        var failureDetails: String? {
            guard case .failed(let message) = self else { return nil }
            return message
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
    var nadirRetouchURL: URL?
    var zenithRetouchURL: URL?
    var controlPointDiagnostics: ControlPointDiagnostics?
    var editableControlPoints: [DiagnosticControlPoint] = []
    var isSuggestingControlPoints = false
    var lastControlPointSuggestionCount: Int?
    var selectedControlPointPairID: ControlPointPair.ID?
    var controlPointLeftImageIndex = 0
    var controlPointRightImageIndex = 1
    var maskDataByImageID: [UUID: Data]
    var protectedMaskDataByImageID: [UUID: Data]
    var maskRevision = 0
    var panoramaRevision = 0
    var sourceMaskIntent = SourceMaskIntent.exclude
    var sourceMaskTool = SourceMaskTool.brush
    private var maskUndoStack: [(MaskKind, UUID, Data?)] = []
    private var sourceMaskUndoStack: [(UUID, Data?, Data?)] = []
    private var repairRenderRevision = 0
    private var stitchOperationID = UUID()

    init(
        project: PanoProject,
        importer: any ImageImporting,
        grouper: any PanoramaGrouping,
        panoramaEngine: any PanoramaEngine,
        exporter: any PanoramaExporting,
        masks: [UUID: Data] = [:],
        protectedMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil,
        zenithOverlayData: Data? = nil,
        nadirRetouchData: Data? = nil,
        zenithRetouchData: Data? = nil
    ) {
        var normalizedProject = project
        normalizedProject.removeUnsupportedControlPoints()
        if let detectedProfile = Self.detectedLensProfile(
            in: normalizedProject.images
        ) {
            if normalizedProject.stitching.lensProfile != detectedProfile {
                normalizedProject.cachedRigImageLines = nil
                normalizedProject.cachedRigSignature = nil
                normalizedProject.nadirRepairPlacement = nil
                normalizedProject.zenithRepairPlacement = nil
            }
            normalizedProject.stitching.lensProfile = detectedProfile
        } else if !StitchingConfiguration.LensProfile.selectableProfiles.contains(
            normalizedProject.stitching.lensProfile
        ) {
            normalizedProject.stitching.lensProfile =
                .sigma8DX
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
        protectedMaskDataByImageID = protectedMasks
        if let savedControlPoints = normalizedProject.controlPoints {
            editableControlPoints = savedControlPoints
            controlPointDiagnostics = ControlPointDiagnostics(
                images: normalizedProject.images,
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
        if let nadirRetouchData {
            nadirRetouchURL = Self.restoreData(
                nadirRetouchData,
                filename: "\(project.id.uuidString)-nadir-retouch.png"
            )
        }
        if let zenithRetouchData {
            zenithRetouchURL = Self.restoreData(
                zenithRetouchData,
                filename: "\(project.id.uuidString)-zenith-retouch.png"
            )
        }
    }

    static func live(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        protectedMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil,
        zenithOverlayData: Data? = nil,
        nadirRetouchData: Data? = nil,
        zenithRetouchData: Data? = nil
    ) -> AppModel {
        AppModel(
            project: project,
            importer: ImageImportService(metadataReader: ImageMetadataReader()),
            grouper: PanoramaGroupingService(),
            panoramaEngine: HuginOpenCVPanoramaEngine(),
            exporter: FilePanoramaExporter(),
            masks: masks,
            protectedMasks: protectedMasks,
            panoramaData: panoramaData,
            nadirOverlayData: nadirOverlayData,
            zenithOverlayData: zenithOverlayData,
            nadirRetouchData: nadirRetouchData,
            zenithRetouchData: zenithRetouchData
        )
    }

    var panorama: PanoramaSet? {
        project.images.isEmpty ? nil : project.panorama
    }

    var sourceDirectoryURL: URL? {
        let directories = project.images.map {
            $0.url.deletingLastPathComponent().standardizedFileURL
        }
        return directories.first
    }

    var selectedPreviewURL: URL? {
        switch selection {
        case .panorama:
            return stitchedResultURL
        case .source(let id):
            return project.images.first { $0.id == id }?.url
                ?? project.images.first?.url
        case .controlPoints:
            return nil
        case .settings, .retouch, .export:
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
        let images = project.images
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

    var isNadirPreviewBlended: Bool {
        project.nadirRepairPlacement?.isBlendedPreview == true
    }

    var canStitch: Bool {
        project.images.filter {
            $0.isEnabled
                && $0.effectiveRole == .alignment
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
            if let detectedProfile = Self.detectedLensProfile(in: sortedImages) {
                project.stitching.lensProfile = detectedProfile
                project.stitching.inputHorizontalFieldOfView =
                    detectedProfile.defaultHorizontalFieldOfView
                    ?? project.stitching.inputHorizontalFieldOfView
            }
            maskDataByImageID = maskDataByImageID.filter { id, _ in
                sortedImages.contains { $0.id == id }
            }
            protectedMaskDataByImageID = protectedMaskDataByImageID.filter {
                id, _ in sortedImages.contains { $0.id == id }
            }
            maskRevision += 1
            skippedFileCount += result.skippedFiles
            stitchedResultURL = nil
            nadirOverlayURL = nil
            controlPointDiagnostics = nil
            project.nadirRepairPlacement = nil
            selection = sortedImages.first.map { .source($0.id) }
            phase = .ready
        }
    }

    var imageMetadataLensProfile: StitchingConfiguration.LensProfile? {
        Self.detectedLensProfile(in: project.images)
    }

    private static func detectedLensProfile(
        in images: [SourceImage]
    ) -> StitchingConfiguration.LensProfile? {
        let alignmentImages = images.filter { $0.effectiveRole == .alignment }
        let profiles = Set(alignmentImages.compactMap { image in
            detectedLensProfile(for: image)
        })
        return profiles.count == 1 ? profiles.first : nil
    }

    private static func detectedLensProfile(
        for image: SourceImage
    ) -> StitchingConfiguration.LensProfile? {
        let model = image.lens.model?.lowercased() ?? ""
        if model.contains("sigma") && model.contains("8") {
            return .sigma8DX
        }
        if (model.contains("nikon") || model.contains("nikkor"))
            && (model.contains("10.5") || model.contains("10,5")) {
            return .nikon105DX
        }
        guard image.lens.kind == .fisheye,
              let focalLength = image.lens.focalLengthIn35mm else {
            return nil
        }
        // New imports store physical focal length here. The two larger
        // ranges keep older projects working when ImageIO supplied a 35 mm
        // equivalent instead.
        if (7...9).contains(focalLength)
            || (11.25...13).contains(focalLength) {
            return .sigma8DX
        }
        if (9.5...11).contains(focalLength)
            || (15...17.5).contains(focalLength) {
            return .nikon105DX
        }
        return nil
    }

    func stitch() {
        // Once a control-point network exists it is the project's authoritative
        // geometry, including every manual add, move, or deletion. Rendering
        // may apply new masks, but only an explicit regeneration command may
        // replace these points.
        guard !editableControlPoints.isEmpty else {
            runWizard()
            return
        }
        stitch(
            controlPoints: editableControlPoints,
            controlPointsAreAuthoritative: true
        )
    }

    func optimizeEditedControlPoints() {
        guard !editableControlPoints.isEmpty, let panorama else { return }
        lastControlPointSuggestionCount = nil
        phase = .optimizingControlPoints
        let points = editableControlPoints
        Task {
            do {
                let result = try await panoramaEngine.optimizeControlPoints(
                    panorama,
                    controlPoints: points,
                    controlPointsAreAuthoritative: true,
                    configuration: project.stitching
                )
                project.applyAutomaticPositioningDecisions(
                    result.automaticPositioningDecisions
                )
                applyOptimizationDiagnostics(
                    result.diagnostics,
                    preserving: points
                )
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func applyOptimizationDiagnostics(
        _ diagnostics: ControlPointDiagnostics,
        preserving originalPoints: [DiagnosticControlPoint]
    ) {
        let projectIndexByFilename = Dictionary(grouping:
            project.images.enumerated(), by: { $0.element.filename }
        ).compactMapValues { matches in
            matches.count == 1 ? matches[0].offset : nil
        }
        let optimizedPoints = diagnostics.cleanedPoints.compactMap {
            point -> DiagnosticControlPoint? in
            guard diagnostics.images.indices.contains(point.firstImage),
                  diagnostics.images.indices.contains(point.secondImage),
                  let first = projectIndexByFilename[
                      diagnostics.images[point.firstImage].filename
                  ],
                  let second = projectIndexByFilename[
                      diagnostics.images[point.secondImage].filename
                  ] else { return nil }
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
        var unusedOptimizedIndices = Set(optimizedPoints.indices)
        editableControlPoints = originalPoints.map { original in
            let match = unusedOptimizedIndices.first {
                optimizedPoints[$0].id == original.id
            } ?? unusedOptimizedIndices
                .filter { optimizedPoints[$0].pair == original.pair }
                .min { left, right in
                    Self.controlPointDistance(
                        optimizedPoints[left], original
                    ) < Self.controlPointDistance(
                        optimizedPoints[right], original
                    )
                }
            guard let match else { return original }
            unusedOptimizedIndices.remove(match)
            var preserved = original
            preserved.error = optimizedPoints[match].error
            return preserved
        }
        saveEditableControlPoints()
        controlPointDiagnostics = ControlPointDiagnostics(
            images: project.images,
            rawPoints: editableControlPoints,
            cleanedPoints: editableControlPoints
        )
    }

    private static func controlPointDistance(
        _ lhs: DiagnosticControlPoint,
        _ rhs: DiagnosticControlPoint
    ) -> Double {
        hypot(lhs.firstX - rhs.firstX, lhs.firstY - rhs.firstY)
            + hypot(lhs.secondX - rhs.secondX, lhs.secondY - rhs.secondY)
    }

    private func stitch(
        controlPoints: [DiagnosticControlPoint]?,
        controlPointsAreAuthoritative: Bool = true
    ) {
        guard let panorama, canStitch else { return }
        let operationID = UUID()
        stitchOperationID = operationID
        repairRenderRevision += 1
        phase = .stitching
        Task {
            do {
                let result = try await panoramaEngine.stitch(
                    panorama,
                    masks: maskDataByImageID,
                    protectedMasks: protectedMaskDataByImageID,
                    controlPoints: controlPoints,
                    controlPointsAreAuthoritative:
                        controlPointsAreAuthoritative,
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
                guard stitchOperationID == operationID else { return }
                project.applyAutomaticPositioningDecisions(
                    result.automaticPositioningDecisions
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
                let newPlacement = result.nadirRepair?.placement
                project.nadirRepairPlacement = newPlacement
                let newZenithPlacement = result.zenithRepair?.placement
                project.zenithRepairPlacement = newZenithPlacement
                if !result.rigImageLines.isEmpty {
                    project.cachedRigImageLines = Dictionary(uniqueKeysWithValues:
                        result.rigImageLines.map { ($0.key.uuidString, $0.value) }
                    )
                    project.cachedRigSignature = project.rigSignature
                }
                panoramaRevision += 1
                selection = .panorama
                if let newPlacement {
                    let overlayURL = try await blendedRepairOverlay(
                        .nadir,
                        panoramaURL: resultURL,
                        placement: newPlacement,
                        projectedRepairURL: result.nadirRepair?.overlayURL
                    )
                    guard stitchOperationID == operationID else { return }
                    nadirOverlayURL = overlayURL
                    project.setNadirRepairPreviewBlended(true)
                }
                if let newZenithPlacement {
                    let overlayURL = try await blendedRepairOverlay(
                        .zenith,
                        panoramaURL: resultURL,
                        placement: newZenithPlacement,
                        projectedRepairURL: result.zenithRepair?.overlayURL
                    )
                    guard stitchOperationID == operationID else { return }
                    zenithOverlayURL = overlayURL
                    project.setZenithRepairPreviewBlended(true)
                }
                panoramaRevision += 1
                phase = .ready
            } catch {
                guard stitchOperationID == operationID else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func applyControlPointDiagnostics(
        _ diagnostics: ControlPointDiagnostics
    ) {
        let existingRepairPoints = editableControlPoints.filter { point in
            !isFrozenRingImage(at: point.firstImage)
                || !isFrozenRingImage(at: point.secondImage)
        }
        let inactiveImagePoints = editableControlPoints.filter { point in
            guard project.images.indices.contains(point.firstImage),
                  project.images.indices.contains(point.secondImage) else {
                return false
            }
            return !project.images[point.firstImage].isEnabled
                || !project.images[point.secondImage].isEnabled
        }
        let projectIndexByID = Dictionary(uniqueKeysWithValues:
            project.images.enumerated().map { ($0.element.id, $0.offset) }
        )
        let refreshedRingPoints: [DiagnosticControlPoint] =
            diagnostics.cleanedPoints.compactMap { point -> DiagnosticControlPoint? in
            guard diagnostics.images.indices.contains(point.firstImage),
                  diagnostics.images.indices.contains(point.secondImage),
                  let first = projectIndexByID[
                      diagnostics.images[point.firstImage].id
                  ],
                  let second = projectIndexByID[
                      diagnostics.images[point.secondImage].id
                  ] else { return nil }
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
        let refreshedIDs = Set(refreshedRingPoints.map(\.id))
        let unreportedRepairPoints = existingRepairPoints.filter {
            !refreshedIDs.contains($0.id)
        }
        let preservedInactivePoints = inactiveImagePoints.filter {
            !refreshedIDs.contains($0.id)
                && !unreportedRepairPoints.map(\.id).contains($0.id)
        }
        editableControlPoints = refreshedRingPoints
            + unreportedRepairPoints
            + preservedInactivePoints
        saveEditableControlPoints()
        controlPointDiagnostics = ControlPointDiagnostics(
            images: project.images,
            rawPoints: editableControlPoints,
            cleanedPoints: editableControlPoints
        )
        selectedControlPointPairID =
            selectedControlPointPairID.flatMap { selected in
                controlPointDiagnostics?.pairs.contains { $0.id == selected }
                    == true
                    ? selected
                    : nil
            } ?? controlPointDiagnostics?.pairs.first?.id
        if let pair = selectedControlPointPairID {
            controlPointLeftImageIndex = pair.firstImage
            controlPointRightImageIndex = pair.secondImage
        }
    }

    private func isFrozenRingImage(at index: Int) -> Bool {
        guard project.images.indices.contains(index) else { return false }
        let image = project.images[index]
        return image.effectiveRole == .alignment
    }

    func moveControlPoint(
        _ id: DiagnosticControlPoint.ID,
        in imageIndex: Int,
        to point: CGPoint
    ) {
        lastControlPointSuggestionCount = nil
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
        lastControlPointSuggestionCount = nil
        editableControlPoints.removeAll { $0.id == id }
        saveEditableControlPoints()
    }

    func removeAllControlPoints(in pair: ControlPointPair.ID) {
        lastControlPointSuggestionCount = nil
        editableControlPoints.removeAll { $0.pair == pair }
        saveEditableControlPoints()
    }

    func removeAllControlPoints() {
        lastControlPointSuggestionCount = nil
        editableControlPoints = []
        saveEditableControlPoints()
    }

    func suggestControlPoints(for pair: ControlPointPair.ID) {
        guard !isSuggestingControlPoints,
              let images = controlPointEditorDiagnostics?.images,
              images.indices.contains(pair.firstImage),
              images.indices.contains(pair.secondImage),
              canShareControlPoints(
                images[pair.firstImage], images[pair.secondImage]
              ) else {
            return
        }
        isSuggestingControlPoints = true
        lastControlPointSuggestionCount = nil
        phase = .suggestingControlPoints
        let horizontalFieldOfView = project.stitching.inputHorizontalFieldOfView
        let lensProfile = project.stitching.lensProfile
        let existingPoints = editableControlPoints
        let cachedLines = project.cachedRigSignature == project.rigSignature
            ? Dictionary(uniqueKeysWithValues:
                (project.cachedRigImageLines ?? [:]).compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                }
              )
            : [:]
        let geometryPrior = ControlPointGeometryPrior(
            images: images,
            cachedImageLines: cachedLines
        )

        Task {
            do {
                let matches = try await Task.detached(priority: .userInitiated) {
                    try OpenCVControlPointMatcher.pair(
                        images: images,
                        pair: pair,
                        horizontalFieldOfView: horizontalFieldOfView,
                        lensProfile: lensProfile
                    )
                }.value
                var candidates = matches
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
                        !existingPoints.contains {
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
                if let geometryPrior {
                    let unfilteredCandidates = candidates
                    candidates = try await Task.detached(
                        priority: .userInitiated
                    ) { [geometryPrior, unfilteredCandidates] in
                        try geometryPrior.filtering(unfilteredCandidates)
                    }.value
                }
                let suggestions = Self.spatiallyDistributedControlPoints(
                    from: candidates,
                    existing: existingPoints.filter { $0.pair == pair },
                    images: images,
                    maximumCount: Self.suggestedControlPointBatchSize
                )
                editableControlPoints.append(contentsOf: suggestions)
                saveEditableControlPoints()
                isSuggestingControlPoints = false
                lastControlPointSuggestionCount = suggestions.count
                phase = .ready
            } catch {
                isSuggestingControlPoints = false
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func regenerateControlPointsForProject() {
        generateControlPointsForProject(stitchesAfterGeneration: false)
    }

    func runWizard() {
        generateControlPointsForProject(stitchesAfterGeneration: true)
    }

    private func generateControlPointsForProject(
        stitchesAfterGeneration: Bool = false
    ) {
        guard !isSuggestingControlPoints,
              let images = controlPointEditorDiagnostics?.images,
              let panorama else {
            return
        }
        let eligible = images.enumerated().filter {
            $0.element.isEnabled && isPositioningCandidate($0.element)
        }
        guard eligible.count >= 2 else { return }
        let matchingImages = eligible.map(\.element)
        let projectIndices = eligible.map(\.offset)
        isSuggestingControlPoints = true
        lastControlPointSuggestionCount = nil
        phase = .suggestingControlPoints
        let horizontalFieldOfView = project.stitching.inputHorizontalFieldOfView
        let lensProfile = project.stitching.lensProfile
        Task {
            do {
                let matches = try await Task.detached(priority: .userInitiated) {
                    try OpenCVControlPointMatcher.ring(
                        images: matchingImages,
                        horizontalFieldOfView: horizontalFieldOfView,
                        lensProfile: lensProfile
                    )
                }.value
                // The ring matcher has already performed geometric and spatial
                // selection. Preserve its full
                // connected network rather than reselecting per pair here.
                var generatedPoints: [DiagnosticControlPoint] = matches.map {
                    DiagnosticControlPoint(
                        firstImage: projectIndices[$0.firstImage],
                        secondImage: projectIndices[$0.secondImage],
                        firstX: $0.firstX,
                        firstY: $0.firstY,
                        secondX: $0.secondX,
                        secondY: $0.secondY
                    )
                }
                let manualRepairIndices = images.indices.filter {
                    images[$0].isEnabled && images[$0].role == .fillOnly
                }
                for repairIndex in manualRepairIndices {
                    for positioningIndex in projectIndices {
                        let pair = ControlPointPair.ID(
                            firstImage: min(repairIndex, positioningIndex),
                            secondImage: max(repairIndex, positioningIndex)
                        )
                        let repairMatches = await Task.detached(
                            priority: .userInitiated
                        ) {
                            (try? OpenCVControlPointMatcher.pair(
                                images: images,
                                pair: pair,
                                horizontalFieldOfView: horizontalFieldOfView,
                                lensProfile: lensProfile
                            )) ?? []
                        }.value
                        generatedPoints += repairMatches.map {
                            DiagnosticControlPoint(
                                firstImage: $0.firstImage,
                                secondImage: $0.secondImage,
                                firstX: $0.firstX,
                                firstY: $0.firstY,
                                secondX: $0.secondX,
                                secondY: $0.secondY
                            )
                        }
                    }
                }
                editableControlPoints = generatedPoints
                saveEditableControlPoints()
                isSuggestingControlPoints = false
                if stitchesAfterGeneration {
                    phase = .ready
                    // Reuse this exact generated network. Running a second
                    // automatic match here can produce a different graph and
                    // discard a valid bridge that the wizard just saved.
                    stitch(
                        controlPoints: editableControlPoints.isEmpty
                            ? nil
                            : editableControlPoints,
                        controlPointsAreAuthoritative: false
                    )
                } else {
                    phase = .optimizingControlPoints
                    let optimized = try await panoramaEngine
                        .optimizeControlPoints(
                            panorama,
                            controlPoints: generatedPoints,
                            controlPointsAreAuthoritative: false,
                            configuration: project.stitching
                        )
                    project.applyAutomaticPositioningDecisions(
                        optimized.automaticPositioningDecisions
                    )
                    applyControlPointDiagnostics(optimized.diagnostics)
                    phase = .ready
                }
            } catch {
                isSuggestingControlPoints = false
                phase = .failed(error.localizedDescription)
            }
        }
    }

    static func spatiallyDistributedControlPoints(
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
            let nextDistance: Double
            if anchors.isEmpty {
                nextIndex = 0
                nextDistance = .greatestFiniteMagnitude
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
                nextDistance = minimumNormalizedDistance(
                    from: remaining[nextIndex],
                    to: anchors,
                    images: images
                )
            }
            // Do not meet the requested count by packing several points into
            // the same local feature cluster. A point must add meaningful
            // coverage in both images; otherwise a smaller set is more useful
            // and honestly signals that this pair is spatially weak.
            if nextDistance < 0.08 {
                break
            }
            selected.append(remaining.remove(at: nextIndex))
        }
        return selected
    }

    private static func minimumNormalizedDistance(
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
        guard first != second,
              project.images.indices.contains(first),
              project.images.indices.contains(second),
              canShareControlPoints(
                project.images[first], project.images[second]
              ) else { return }
        controlPointLeftImageIndex = first
        controlPointRightImageIndex = second
        lastControlPointSuggestionCount = nil
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
        guard canShareControlPoints(
            images[mainIndex], images[rightIndex]
        ) else { return }
        selectControlPointImages(mainIndex, rightIndex)
        selection = .controlPoints
    }

    private func isPositioningCandidate(_ image: SourceImage) -> Bool {
        image.role != .fillOnly
    }

    private func canShareControlPoints(
        _ first: SourceImage,
        _ second: SourceImage
    ) -> Bool {
        first.role != .fillOnly || second.role != .fillOnly
    }

    @discardableResult
    func addPredictedControlPoint(
        to pair: ControlPointPair.ID,
        point: CGPoint,
        in imageIndex: Int
    ) -> DiagnosticControlPoint.ID {
        lastControlPointSuggestionCount = nil
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

    func predictedControlPointCounterpart(
        to pair: ControlPointPair.ID,
        point: CGPoint,
        in imageIndex: Int
    ) -> (point: CGPoint, imageIndex: Int) {
        let clickedFirstImage = imageIndex == pair.firstImage
        return (
            predictedCounterpart(
                for: point,
                in: pair,
                clickedFirstImage: clickedFirstImage
            ),
            clickedFirstImage ? pair.secondImage : pair.firstImage
        )
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
        guard !candidates.isEmpty else {
            return counterpartCenter(
                for: pair,
                clickedFirstImage: clickedFirstImage
            )
        }

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
        guard totalWeight > 0 else {
            return counterpartCenter(
                for: pair,
                clickedFirstImage: clickedFirstImage
            )
        }
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
        let images = project.images
        let index = clickedFirstImage ? pair.secondImage : pair.firstImage
        guard let image = images.indices.contains(index) ? images[index] : nil
        else { return point }
        let size = counterpartCoordinateSize(for: image)
        guard point.x.isFinite,
              point.y.isFinite,
              point.x >= 0,
              point.y >= 0,
              point.x <= size.width,
              point.y <= size.height else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        return point
    }

    private func counterpartCenter(
        for pair: ControlPointPair.ID,
        clickedFirstImage: Bool
    ) -> CGPoint {
        let images = project.images
        let index = clickedFirstImage ? pair.secondImage : pair.firstImage
        guard let image = images.indices.contains(index) ? images[index] : nil
        else { return .zero }
        let size = counterpartCoordinateSize(for: image)
        return CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func counterpartCoordinateSize(for image: SourceImage) -> CGSize {
        let rawSize = CGSize(
            width: image.pixelWidth,
            height: image.pixelHeight
        )
        guard let source = CGImageSourceCreateWithURL(image.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let value = properties[kCGImagePropertyOrientation] as? NSNumber,
              let orientation = CGImagePropertyOrientation(
                  rawValue: value.uint32Value
              ) else {
            return rawSize
        }
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: rawSize.height, height: rawSize.width)
        default:
            return rawSize
        }
    }

    private func saveEditableControlPoints() {
        editableControlPoints = editableControlPoints.filter { point in
            guard project.images.indices.contains(point.firstImage),
                  project.images.indices.contains(point.secondImage) else {
                return false
            }
            return canShareControlPoints(
                project.images[point.firstImage],
                project.images[point.secondImage]
            )
        }
        project.controlPoints = editableControlPoints
        project.modifiedAt = Date(
            timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)
        )
    }

    func removeSelectedSourceImage() {
        guard case .source(let id) = selection else { return }
        removeSourceImage(id)
    }

    func removeSourceImage(_ id: SourceImage.ID) {
        guard let index = project.images.firstIndex(where: { $0.id == id })
        else { return }

        stitchOperationID = UUID()
        project.removeImage(at: index)
        let images = project.images
        editableControlPoints = project.controlPoints ?? []
        selectedControlPointPairID = nil
        maskDataByImageID[id] = nil
        protectedMaskDataByImageID[id] = nil
        maskUndoStack.removeAll { $0.1 == id }
        maskRevision += 1
        repairRenderRevision += 1
        stitchedResultURL = nil
        nadirOverlayURL = nil
        zenithOverlayURL = nil
        controlPointDiagnostics = nil
        phase = .ready
        panoramaRevision += 1

        if images.isEmpty {
            selection = nil
        } else {
            selection = .source(images[min(index, images.count - 1)].id)
        }
    }

    func setRole(_ role: SourceImage.Role, for imageID: UUID) {
        repairRenderRevision += 1
        project.setRole(role, for: imageID)
        editableControlPoints = project.controlPoints ?? []
        controlPointDiagnostics = ControlPointDiagnostics(
            images: project.images,
            rawPoints: editableControlPoints,
            cleanedPoints: editableControlPoints
        )
        selectedControlPointPairID = nil
        stitchedResultURL = nil
        nadirOverlayURL = nil
        zenithOverlayURL = nil
        panoramaRevision += 1
    }

    func setRepairArea(
        _ direction: SourceImage.Direction,
        for imageID: UUID
    ) {
        repairRenderRevision += 1
        let changesGeometry = project.images.first(where: { $0.id == imageID })?
            .role != .fillOnly
        project.setRepairArea(direction, for: imageID)
        if changesGeometry {
            clearEditableControlPointsAfterGeometryChange()
        } else {
            editableControlPoints = project.controlPoints ?? []
            controlPointDiagnostics = nil
            selectedControlPointPairID = nil
        }
        stitchedResultURL = nil
        nadirOverlayURL = nil
        zenithOverlayURL = nil
        panoramaRevision += 1
    }

    func toggleSourceImageEnabled(_ imageID: UUID) {
        stitchOperationID = UUID()
        repairRenderRevision += 1
        project.toggleImageEnabled(imageID)
        stitchedResultURL = nil
        nadirOverlayURL = nil
        zenithOverlayURL = nil
        phase = .ready
        panoramaRevision += 1
    }

    private func clearEditableControlPointsAfterGeometryChange() {
        editableControlPoints = []
        controlPointDiagnostics = nil
        selectedControlPointPairID = nil
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
        panoramaRevision += 1
    }

    func maskData(for id: UUID) -> Data? {
        switch activeMaskKind {
        case .protected: protectedMaskDataByImageID[id]
        case .panorama: maskDataByImageID[id]
        }
    }

    func setMaskData(_ data: Data?, for id: UUID) {
        let kind = activeMaskKind
        if kind == .protected {
            maskUndoStack.append((kind, id, protectedMaskDataByImageID[id]))
            protectedMaskDataByImageID[id] = data
        } else {
            maskUndoStack.append((kind, id, maskDataByImageID[id]))
            maskDataByImageID[id] = data
        }
        maskRevision += 1
        if refreshRepairOverlayIfPossible(for: id) {
            return
        }
        repairRenderRevision += 1
        stitchedResultURL = nil
        nadirOverlayURL = nil
        project.nadirRepairPlacement = nil
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

    func setSourceMasks(
        red: Data?, green: Data?, for id: UUID
    ) {
        sourceMaskUndoStack.append((
            id, maskDataByImageID[id], protectedMaskDataByImageID[id]
        ))
        maskDataByImageID[id] = red
        protectedMaskDataByImageID[id] = green
        maskRevision += 1
        // A source mask on an already registered pole repair only changes
        // which repair pixels are visible. Re-render that overlay against the
        // frozen panorama instead of discarding the placement and forcing the
        // global rig through another geometry solve.
        if refreshRepairOverlayIfPossible(for: id) {
            return
        }
        repairRenderRevision += 1
        stitchedResultURL = nil
        nadirOverlayURL = nil
        project.nadirRepairPlacement = nil
        panoramaRevision += 1
    }

    func invertSelectedMask() {
        guard let image = selectedSourceImage,
              let currentData = maskData(for: image.id),
              let invertedData = SourceMaskRasterizer.inverted(
                  currentData,
                  width: image.pixelWidth,
                  height: image.pixelHeight,
                  protectedArea: activeMaskKind == .protected
              ) else {
            return
        }
        setMaskData(invertedData, for: image.id)
    }

    var canUndoMask: Bool {
        !sourceMaskUndoStack.isEmpty || !maskUndoStack.isEmpty
    }

    func undoMask() {
        if let (id, red, green) = sourceMaskUndoStack.popLast() {
            maskDataByImageID[id] = red
            protectedMaskDataByImageID[id] = green
            maskRevision += 1
            repairRenderRevision += 1
            stitchedResultURL = nil
            nadirOverlayURL = nil
            project.nadirRepairPlacement = nil
            panoramaRevision += 1
            return
        }
        guard let (kind, id, data) = maskUndoStack.popLast() else { return }
        if kind == .protected {
            protectedMaskDataByImageID[id] = data
        } else {
            maskDataByImageID[id] = data
        }
        maskRevision += 1
        if refreshRepairOverlayIfPossible(for: id) {
            return
        }
        repairRenderRevision += 1
        stitchedResultURL = nil
        nadirOverlayURL = nil
        project.nadirRepairPlacement = nil
        panoramaRevision += 1
    }

    var activeMaskKind: MaskKind {
        switch sourceMaskIntent {
        case .exclude: .panorama
        case .protect: .protected
        case .erase: .panorama
        }
    }

    func showSelectedRepairPreview() {
        guard phase == .ready,
              let image = selectedSourceImage,
              image.effectiveRole == .fillOnly else { return }
        renderBlendedRepairPreview(
            image.effectiveDirection == .zenith ? .zenith : .nadir
        )
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

    func retouchURL(for pole: PanoramaPole) -> URL? {
        pole == .nadir ? nadirRetouchURL : zenithRetouchURL
    }

    func aiRetouchPrompt(for pole: PanoramaPole) -> String? {
        project.aiRetouchPrompt(for: pole)
    }

    func setAIRetouchPrompt(_ prompt: String, for pole: PanoramaPole) {
        project.setAIRetouchPrompt(prompt, for: pole)
    }

    func exportRetouchPlate(
        for pole: PanoramaPole,
        to destinationURL: URL
    ) {
        guard let panoramaURL = stitchedResultURL, phase == .ready else { return }
        let repairOverlayURL = pole == .nadir
            ? (project.nadirRepairPlacement == nil ? nil : nadirOverlayURL)
            : (project.zenithRepairPlacement == nil ? nil : zenithOverlayURL)
        let existingRetouchURL = retouchURL(for: pole)
        phase = .retouching
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PoleRetouchService().exportPlate(
                        panoramaURL: panoramaURL,
                        repairOverlayURL: repairOverlayURL,
                        existingRetouchURL: existingRetouchURL,
                        pole: pole,
                        to: destinationURL
                    )
                }.value
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func importRetouchPlate(
        for pole: PanoramaPole,
        from sourceURL: URL
    ) {
        guard stitchedResultURL != nil, phase == .ready else { return }
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/Retouch/\(project.id.uuidString)",
            directoryHint: .isDirectory
        )
        let destinationURL = directory.appending(
            path: "\(pole.rawValue)-retouch.png"
        )
        phase = .retouching
        Task {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try await Task.detached(priority: .userInitiated) {
                    try PoleRetouchService().prepareImportedPlate(
                        from: sourceURL,
                        pole: pole,
                        to: destinationURL
                    )
                }.value
                if pole == .nadir {
                    nadirRetouchURL = destinationURL
                } else {
                    zenithRetouchURL = destinationURL
                }
                selection = .panorama
                panoramaRevision += 1
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func createAIRetouchSource(
        for pole: PanoramaPole
    ) async throws -> AIRetouchSource {
        guard let panoramaURL = stitchedResultURL, phase == .ready else {
            throw AIRetouchError.panoramaUnavailable
        }
        let repairOverlayURL = pole == .nadir
            ? (project.nadirRepairPlacement == nil ? nil : nadirOverlayURL)
            : (project.zenithRepairPlacement == nil ? nil : zenithOverlayURL)
        let existingRetouchURL = retouchURL(for: pole)
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/AIRetouch/\(project.id.uuidString)/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let sourceURL = directory.appending(path: "\(pole.rawValue)-source.png")

        phase = .retouching
        defer {
            if phase == .retouching { phase = .ready }
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            try await Task.detached(priority: .userInitiated) {
                try PoleRetouchService().exportPlate(
                    panoramaURL: panoramaURL,
                    repairOverlayURL: repairOverlayURL,
                    existingRetouchURL: existingRetouchURL,
                    pole: pole,
                    to: sourceURL
                )
            }.value
            try Task.checkCancellation()
            return AIRetouchSource(
                pole: pole,
                directoryURL: directory,
                sourceURL: sourceURL
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func createAIRetouchPreview(
        source: AIRetouchSource,
        for pole: PanoramaPole,
        maskData: Data?,
        prompt: String,
        apiKey: String
    ) async throws -> AIRetouchPreview {
        guard stitchedResultURL != nil,
              phase == .ready,
              source.pole == pole,
              FileManager.default.fileExists(atPath: source.sourceURL.path)
        else {
            throw AIRetouchError.panoramaUnavailable
        }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { throw AIRetouchError.emptyPrompt }

        let directory = source.directoryURL.appending(
            path: "Previews/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let rawEditedURL = directory.appending(path: "\(pole.rawValue)-raw.png")
        let editedURL = directory.appending(path: "\(pole.rawValue)-edited.png")
        let preparedURL = directory.appending(path: "\(pole.rawValue)-prepared.png")
        let apiMaskURL = directory.appending(path: "\(pole.rawValue)-mask.png")

        phase = .retouching
        defer {
            if phase == .retouching { phase = .ready }
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let requestData = try await Task.detached(priority: .userInitiated) {
            let sourceData = try Data(contentsOf: source.sourceURL)
            guard let maskData else {
                return (sourceData, Optional<Data>.none)
            }
            try PoleRetouchService().makeOpenAIEditMask(
                from: maskData,
                pole: pole,
                to: apiMaskURL
            )
            return (sourceData, try Data(contentsOf: apiMaskURL))
        }.value
        let editedData = try await OpenAIImageEditService(apiKey: apiKey).edit(
            imageData: requestData.0,
            maskData: requestData.1,
            filename: "\(pole.rawValue).png",
            prompt: trimmedPrompt,
            size: PoleRetouchService.plateSize
        )
        try Task.checkCancellation()

        try await Task.detached(priority: .userInitiated) {
            try editedData.write(to: rawEditedURL, options: .atomic)
            if let maskData {
                try PoleRetouchService().prepareMaskedAIEdit(
                    sourceURL: source.sourceURL,
                    editedURL: rawEditedURL,
                    userMaskData: maskData,
                    pole: pole,
                    previewURL: editedURL,
                    preparedURL: preparedURL
                )
            } else {
                try editedData.write(to: editedURL, options: .atomic)
                try PoleRetouchService().prepareImportedPlate(
                    from: rawEditedURL,
                    pole: pole,
                    to: preparedURL
                )
            }
        }.value
        return AIRetouchPreview(
            pole: pole,
            directoryURL: directory,
            sourceURL: source.sourceURL,
            editedURL: editedURL,
            preparedURL: preparedURL
        )
    }

    func applyAIRetouchPreview(_ preview: AIRetouchPreview) throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/Retouch/\(project.id.uuidString)",
            directoryHint: .isDirectory
        )
        let destinationURL = directory.appending(
            path: "\(preview.pole.rawValue)-retouch.png"
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(contentsOf: preview.preparedURL).write(
            to: destinationURL,
            options: .atomic
        )
        if preview.pole == .nadir {
            nadirRetouchURL = destinationURL
        } else {
            zenithRetouchURL = destinationURL
        }
        selection = .panorama
        panoramaRevision += 1
    }

    func discardAIRetouchPreview(_ preview: AIRetouchPreview) {
        try? FileManager.default.removeItem(at: preview.directoryURL)
    }

    func discardAIRetouchSource(_ source: AIRetouchSource) {
        try? FileManager.default.removeItem(at: source.directoryURL)
    }

    func removeRetouch(for pole: PanoramaPole) {
        guard retouchURL(for: pole) != nil else { return }
        if pole == .nadir {
            nadirRetouchURL = nil
        } else {
            zenithRetouchURL = nil
        }
        panoramaRevision += 1
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
                    nadirRetouchURL: nadirRetouchURL,
                    zenithRetouchURL: zenithRetouchURL,
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

    var nadirRetouchData: Data? {
        guard let nadirRetouchURL else { return nil }
        return try? Data(contentsOf: nadirRetouchURL)
    }

    var zenithRetouchData: Data? {
        guard let zenithRetouchURL else { return nil }
        return try? Data(contentsOf: zenithRetouchURL)
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
        for imageID: UUID
    ) -> Bool {
        guard
            let repairImage = project.images.first(where: {
                $0.id == imageID
                    && $0.effectiveRole == .fillOnly
            }),
            let placement = repairImage.effectiveDirection == .zenith
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
        let horizontalFieldOfView = placement.sourceHorizontalFieldOfView
            ?? project.stitching.inputHorizontalFieldOfView
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/Repairs/\(project.id.uuidString)",
                directoryHint: .isDirectory
            )
        let outputURL = outputDirectory.appending(
            path: "\(UUID().uuidString)-\(repairImage.effectiveDirection.rawValue)-overlay.png"
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
                if repairImage.effectiveDirection == .zenith {
                    zenithOverlayURL = outputURL
                    project.setZenithRepairPreviewBlended(false)
                } else {
                    nadirOverlayURL = outputURL
                    project.setNadirRepairPreviewBlended(false)
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
                    && $0.effectiveRole == .fillOnly
                    && $0.effectiveDirection
                        == (pole == .zenith ? .zenith : .nadir)
            })
        else {
            return
        }

        repairRenderRevision += 1
        let revision = repairRenderRevision
        let exclusionMaskData = maskDataByImageID[repairImage.id]
        let horizontalFieldOfView = placement.sourceHorizontalFieldOfView
            ?? project.stitching.inputHorizontalFieldOfView
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

    private func blendedRepairOverlay(
        _ pole: PanoramaPole,
        panoramaURL: URL,
        placement: NadirRepairPlacement,
        projectedRepairURL: URL? = nil
    ) async throws -> URL {
        guard let repairImage = project.images.first(where: {
            $0.id == placement.imageID
                && $0.effectiveRole == .fillOnly
                && $0.effectiveDirection
                    == (pole == .zenith ? .zenith : .nadir)
        }) else {
            throw PanoramaEngineError.stitchingFailed(
                "\(pole.displayName)bilden saknas i projektet."
            )
        }
        phase = .blendingRepair
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/Repairs/\(project.id.uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let outputURL = outputDirectory.appending(
            path: "\(UUID().uuidString)-\(pole.rawValue)-wand-blended.png"
        )
        let exclusionMaskData = maskDataByImageID[repairImage.id]
        let horizontalFieldOfView = placement.sourceHorizontalFieldOfView
            ?? project.stitching.inputHorizontalFieldOfView
        try await Task.detached(priority: .userInitiated) {
            try OpenCVNadirRepairRegistrar.renderBlendedOverlay(
                panoramaURL: panoramaURL,
                repairImage: repairImage,
                exclusionMaskData: exclusionMaskData,
                projectedRepairURL: projectedRepairURL,
                horizontalFieldOfView: horizontalFieldOfView,
                pole: pole,
                placement: placement,
                outputURL: outputURL
            )
        }.value
        return outputURL
    }

}
