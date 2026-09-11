import Foundation
import Observation

enum ProjectSelection: Hashable {
    case panorama
    case retouch
    case export
    case source(SourceImage.ID)
}

@MainActor
@Observable
final class AppModel {
    enum SourceMaskIntent: Hashable { case exclude, protect, erase }
    enum MaskKind: Hashable { case panorama, protected }

    private struct MaskSnapshot {
        let red: Data?
        let green: Data?
    }

    enum Phase: Equatable {
        case ready, importing, stitching, retouching, exporting
        case failed(String)

        var message: String {
            switch self {
            case .ready: "Redo"
            case .importing: "Läser bilder och metadata…"
            case .stitching: "Sammanfogar panorama…"
            case .retouching: "Retuscherar polbild…"
            case .exporting: "Exporterar…"
            case .failed(let message): message
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
    private var stitchTask: Task<Void, Never>?
    private var stitchOperationID = UUID()
    private var maskUndoHistory: [UUID: [MaskSnapshot]] = [:]

    var project: PanoProject
    var selection: ProjectSelection? {
        didSet {
            isSourceMaskEditing = selectedSourceImage != nil
        }
    }
    var phase: Phase = .ready
    var isImporterPresented = false
    var skippedFileCount = 0
    var stitchedResultURL: URL?
    var panoramaViewpoint = PanoramaViewpoint()
    var nadirOverlayURL: URL?
    var zenithOverlayURL: URL?
    var nadirRetouchURL: URL?
    var zenithRetouchURL: URL?
    var nadirAIRetouchResultURL: URL?
    var zenithAIRetouchResultURL: URL?
    var nadirAIRetouchMaskData: Data?
    var zenithAIRetouchMaskData: Data?
    var maskDataByImageID: [UUID: Data]
    var protectedMaskDataByImageID: [UUID: Data]
    var maskRevision = 0
    var panoramaRevision = 0
    var aiRetouchMaskRevision = 0
    var sourceMaskIntent = SourceMaskIntent.exclude
    var sourceMaskTool = SourceMaskTool.brush
    var isSourceMaskEditing = false
    var stitchProgress = 0.0
    var stitchStage = ""
    var lastStitchCoverage: Double?
    var lastStitchHoleCount: Int?
    var usedAlignmentCache = false

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
        zenithRetouchData: Data? = nil,
        nadirAIRetouchResultData: Data? = nil,
        zenithAIRetouchResultData: Data? = nil,
        nadirAIRetouchMaskData: Data? = nil,
        zenithAIRetouchMaskData: Data? = nil
    ) {
        var migrated = project
        migrated.migrateToCurrentFormat()
        self.project = migrated
        self.importer = importer
        self.grouper = grouper
        self.panoramaEngine = panoramaEngine
        self.exporter = exporter
        maskDataByImageID = masks
        protectedMaskDataByImageID = protectedMasks
        panoramaViewpoint = migrated.previewViewpoint ?? PanoramaViewpoint()
        selection = migrated.images.first.map { .source($0.id) }
        isSourceMaskEditing = !migrated.images.isEmpty
        stitchedResultURL = panoramaData.flatMap {
            Self.restoreData($0, filename: "\(migrated.id)-panorama.jpg")
        }
        nadirOverlayURL = nadirOverlayData.flatMap {
            Self.restoreData($0, filename: "\(migrated.id)-nadir-overlay.png")
        }
        zenithOverlayURL = zenithOverlayData.flatMap {
            Self.restoreData($0, filename: "\(migrated.id)-zenith-overlay.png")
        }
        nadirRetouchURL = nadirRetouchData.flatMap {
            Self.restoreData($0, filename: "\(migrated.id)-nadir-retouch.png")
        }
        zenithRetouchURL = zenithRetouchData.flatMap {
            Self.restoreData($0, filename: "\(migrated.id)-zenith-retouch.png")
        }
        nadirAIRetouchResultURL = nadirAIRetouchResultData.flatMap {
            Self.restoreData($0, filename: "\(migrated.id)-nadir-ai-result.png")
        }
        zenithAIRetouchResultURL = zenithAIRetouchResultData.flatMap {
            Self.restoreData($0, filename: "\(migrated.id)-zenith-ai-result.png")
        }
        self.nadirAIRetouchMaskData = nadirAIRetouchMaskData
        self.zenithAIRetouchMaskData = zenithAIRetouchMaskData
    }

    static func live(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        protectedMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil,
        zenithOverlayData: Data? = nil,
        nadirRetouchData: Data? = nil,
        zenithRetouchData: Data? = nil,
        nadirAIRetouchResultData: Data? = nil,
        zenithAIRetouchResultData: Data? = nil,
        nadirAIRetouchMaskData: Data? = nil,
        zenithAIRetouchMaskData: Data? = nil
    ) -> AppModel {
        AppModel(
            project: project,
            importer: ImageImportService(metadataReader: ImageMetadataReader()),
            grouper: PanoramaGroupingService(),
            panoramaEngine: OpenCVPanoramaEngine(),
            exporter: FilePanoramaExporter(),
            masks: masks,
            protectedMasks: protectedMasks,
            panoramaData: panoramaData,
            nadirOverlayData: nadirOverlayData,
            zenithOverlayData: zenithOverlayData,
            nadirRetouchData: nadirRetouchData,
            zenithRetouchData: zenithRetouchData,
            nadirAIRetouchResultData: nadirAIRetouchResultData,
            zenithAIRetouchResultData: zenithAIRetouchResultData,
            nadirAIRetouchMaskData: nadirAIRetouchMaskData,
            zenithAIRetouchMaskData: zenithAIRetouchMaskData
        )
    }

    var panorama: PanoramaSet? { project.images.isEmpty ? nil : project.panorama }
    var sourceDirectoryURL: URL? { project.images.first?.url.deletingLastPathComponent() }

    var selectedPreviewURL: URL? {
        switch selection {
        case .panorama: stitchedResultURL
        case .source(let id):
            project.images.first { $0.id == id }?.url ?? project.images.first?.url
        case .retouch, .export: nil
        case nil: stitchedResultURL ?? project.images.first?.url
        }
    }

    var selectedSourceImage: SourceImage? {
        guard case .source(let id) = selection else { return nil }
        return project.images.first { $0.id == id }
    }

    var isShowingStitchedPanorama: Bool {
        selection == .panorama && stitchedResultURL != nil
    }

    var canStitch: Bool {
        project.images.filter(\.isEnabled).count >= 2 && phase == .ready
    }

    var canCancelStitch: Bool { phase == .stitching }
    var canExportHTML: Bool { stitchedResultURL != nil && phase == .ready }

    func setPanoramaViewpoint(_ viewpoint: PanoramaViewpoint) {
        guard panoramaViewpoint != viewpoint else { return }
        panoramaViewpoint = viewpoint
        project.previewViewpoint = viewpoint
    }

    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty, phase != .importing else { return }
        phase = .importing
        Task {
            let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
            let result = await importer.load(from: urls)
            let unique = Dictionary(
                (project.images + result.images).map {
                    ($0.url.standardizedFileURL, $0)
                },
                uniquingKeysWith: { current, _ in current }
            ).map(\.value)
            let images = grouper.group(unique).flatMap(\.images)
            project.replaceImages(images)
            retainMasks(for: images)
            skippedFileCount += result.skippedFiles
            invalidatePanorama()
            selection = images.first.map { .source($0.id) }
            phase = .ready
        }
    }

    func selectSourceImage(_ id: SourceImage.ID) {
        guard project.images.contains(where: { $0.id == id }) else { return }
        selection = .source(id)
    }

    func removeSelectedSourceImage() {
        guard case .source(let id) = selection else { return }
        removeSourceImage(id)
    }

    func removeSourceImage(_ id: SourceImage.ID) {
        guard let index = project.images.firstIndex(where: { $0.id == id }) else {
            return
        }
        cancelStitch()
        project.removeImage(at: index)
        maskDataByImageID[id] = nil
        protectedMaskDataByImageID[id] = nil
        maskUndoHistory[id] = nil
        maskRevision += 1
        invalidatePanorama()
        selection = project.images.isEmpty
            ? nil
            : .source(project.images[min(index, project.images.count - 1)].id)
    }

    func moveSourceImageToTrash(_ id: SourceImage.ID) throws {
        guard let image = project.images.first(where: { $0.id == id }) else {
            return
        }
        let accessed = image.url.startAccessingSecurityScopedResource()
        defer {
            if accessed { image.url.stopAccessingSecurityScopedResource() }
        }
        try FileManager.default.trashItem(
            at: image.url,
            resultingItemURL: nil
        )
        removeSourceImage(id)
    }

    func toggleSourceImageEnabled(_ id: SourceImage.ID) {
        cancelStitch()
        project.toggleImageEnabled(id)
        invalidatePanorama()
    }

    func setSourceImageRole(_ id: SourceImage.ID, role: SourceImage.Role) {
        guard let index = project.images.firstIndex(where: { $0.id == id }),
              project.images[index].role != role else { return }
        cancelStitch()
        project.images[index].role = role
        invalidatePanorama()
    }

    func rotateSourceImageLeft(_ id: SourceImage.ID) {
        guard selectedSourceImage?.id == id else { return }
        do {
            let red = try SourceImageRaster.rotatePNGLeft(
                maskDataByImageID[id]
            )
            let green = try SourceImageRaster.rotatePNGLeft(
                protectedMaskDataByImageID[id]
            )
            let history = try (maskUndoHistory[id] ?? []).map { snapshot in
                MaskSnapshot(
                    red: try SourceImageRaster.rotatePNGLeft(snapshot.red),
                    green: try SourceImageRaster.rotatePNGLeft(snapshot.green)
                )
            }
            project.rotateImageLeft(id)
            maskDataByImageID[id] = red
            protectedMaskDataByImageID[id] = green
            maskUndoHistory[id] = history
            maskRevision += 1
            invalidatePanorama()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stitch() {
        guard let panorama, canStitch else { return }
        let operationID = UUID()
        stitchOperationID = operationID
        stitchProgress = 0
        stitchStage = "Förbereder panoramamotor…"
        phase = .stitching
        let masks = maskDataByImageID
        let protectedMasks = protectedMaskDataByImageID
        stitchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await panoramaEngine.stitch(
                    panorama,
                    masks: masks,
                    protectedMasks: protectedMasks
                ) { [weak self] fraction, stage in
                    Task { @MainActor in
                        guard let self,
                              self.stitchOperationID == operationID else { return }
                        self.stitchProgress = fraction
                        self.stitchStage = stage
                    }
                }
                guard stitchOperationID == operationID else { return }
                stitchedResultURL = result.url
                nadirOverlayURL = nil
                zenithOverlayURL = nil
                nadirRetouchURL = nil
                zenithRetouchURL = nil
                nadirAIRetouchResultURL = nil
                zenithAIRetouchResultURL = nil
                lastStitchCoverage = result.coveragePercent
                lastStitchHoleCount = result.holeCount
                usedAlignmentCache = result.usedAlignmentCache
                stitchProgress = 1
                stitchStage = "Panoramat är klart"
                selection = .panorama
                panoramaRevision += 1
                phase = .ready
            } catch is CancellationError {
                guard stitchOperationID == operationID else { return }
                phase = .ready
                stitchStage = "Panoramabygget avbröts"
            } catch {
                guard stitchOperationID == operationID else { return }
                phase = .failed(error.localizedDescription)
            }
            stitchTask = nil
        }
    }

    func cancelStitch() {
        guard let stitchTask else { return }
        stitchTask.cancel()
        stitchStage = "Avbryter panoramabygget…"
    }

    func maskData(for id: UUID) -> Data? {
        activeMaskKind == .protected
            ? protectedMaskDataByImageID[id]
            : maskDataByImageID[id]
    }

    func setMaskData(_ data: Data?, for id: UUID) {
        let kind = activeMaskKind
        let previous = kind == .protected
            ? protectedMaskDataByImageID[id]
            : maskDataByImageID[id]
        guard previous != data else { return }
        recordMaskUndo(for: id)
        if kind == .protected {
            protectedMaskDataByImageID[id] = data
        } else {
            maskDataByImageID[id] = data
        }
        maskRevision += 1
        invalidatePanorama()
    }

    func clearSelectedMask() {
        guard let image = selectedSourceImage,
              maskData(for: image.id) != nil else { return }
        setMaskData(nil, for: image.id)
    }

    func setSourceMasks(red: Data?, green: Data?, for id: UUID) {
        guard maskDataByImageID[id] != red
                || protectedMaskDataByImageID[id] != green else { return }
        recordMaskUndo(for: id)
        maskDataByImageID[id] = red
        protectedMaskDataByImageID[id] = green
        maskRevision += 1
        invalidatePanorama()
    }

    func invertSelectedMask() {
        guard let image = selectedSourceImage,
              let data = maskData(for: image.id),
              let inverted = SourceMaskRasterizer.inverted(
                data,
                width: image.orientedPixelWidth,
                height: image.orientedPixelHeight,
                protectedArea: activeMaskKind == .protected
              ) else { return }
        setMaskData(inverted, for: image.id)
    }

    var canUndoMask: Bool {
        guard isSourceMaskEditing,
              let id = selectedSourceImage?.id else { return false }
        return maskUndoHistory[id]?.isEmpty == false
    }

    func undoMask() {
        guard isSourceMaskEditing,
              let id = selectedSourceImage?.id,
              let snapshot = maskUndoHistory[id]?.popLast() else { return }
        maskDataByImageID[id] = snapshot.red
        protectedMaskDataByImageID[id] = snapshot.green
        maskRevision += 1
        invalidatePanorama()
    }

    var activeMaskKind: MaskKind {
        sourceMaskIntent == .protect ? .protected : .panorama
    }

    func retouchURL(for pole: PanoramaPole) -> URL? {
        pole == .nadir ? nadirRetouchURL : zenithRetouchURL
    }

    func aiRetouchResultURL(for pole: PanoramaPole) -> URL? {
        pole == .nadir ? nadirAIRetouchResultURL : zenithAIRetouchResultURL
    }

    func aiRetouchMaskData(for pole: PanoramaPole) -> Data? {
        pole == .nadir ? nadirAIRetouchMaskData : zenithAIRetouchMaskData
    }

    func setAIRetouchMaskData(_ data: Data?, for pole: PanoramaPole) {
        guard aiRetouchMaskData(for: pole) != data else { return }
        if pole == .nadir { nadirAIRetouchMaskData = data }
        else { zenithAIRetouchMaskData = data }
        aiRetouchMaskRevision += 1
    }

    func aiRetouchPrompt(for pole: PanoramaPole) -> String? {
        project.aiRetouchPrompt(for: pole)
    }

    func setAIRetouchPrompt(_ prompt: String, for pole: PanoramaPole) {
        project.setAIRetouchPrompt(prompt, for: pole)
    }

    func clearAIRetouchPrompt(for pole: PanoramaPole) {
        project.clearAIRetouchPrompt(for: pole)
    }

    func exportRetouchPlate(for pole: PanoramaPole, to destinationURL: URL) {
        guard let panoramaURL = stitchedResultURL, phase == .ready else { return }
        let overlayURL = pole == .nadir ? nadirOverlayURL : zenithOverlayURL
        let existingURL = retouchURL(for: pole)
        phase = .retouching
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PoleRetouchService().exportPlate(
                        panoramaURL: panoramaURL,
                        repairOverlayURL: overlayURL,
                        existingRetouchURL: existingURL,
                        pole: pole,
                        to: destinationURL
                    )
                }.value
                phase = .ready
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

    func importRetouchPlate(for pole: PanoramaPole, from sourceURL: URL) {
        guard stitchedResultURL != nil, phase == .ready else { return }
        let directory = retouchDirectory
        let destination = directory.appending(path: "\(pole.rawValue)-retouch.png")
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
                        to: destination
                    )
                }.value
                if let oldResultURL = aiRetouchResultURL(for: pole) {
                    try? FileManager.default.removeItem(at: oldResultURL)
                }
                setAIRetouchResultURL(nil, for: pole)
                setRetouchURL(destination, for: pole)
                selection = .panorama
                panoramaRevision += 1
                phase = .ready
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

    func createAIRetouchSource(for pole: PanoramaPole) async throws
        -> AIRetouchSource {
        guard let panoramaURL = stitchedResultURL, phase == .ready else {
            throw AIRetouchError.panoramaUnavailable
        }
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/AIRetouch/\(project.id)/\(UUID())",
            directoryHint: .isDirectory
        )
        let sourceURL = directory.appending(path: "\(pole.rawValue)-source.png")
        let overlayURL = pole == .nadir ? nadirOverlayURL : zenithOverlayURL
        phase = .retouching
        defer { if phase == .retouching { phase = .ready } }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            try await Task.detached(priority: .userInitiated) {
                try PoleRetouchService().exportPlate(
                    panoramaURL: panoramaURL,
                    repairOverlayURL: overlayURL,
                    existingRetouchURL: nil,
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
        else { throw AIRetouchError.panoramaUnavailable }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw AIRetouchError.emptyPrompt }
        let directory = source.directoryURL.appending(
            path: "Previews/\(UUID())",
            directoryHint: .isDirectory
        )
        let editedURL = directory.appending(path: "\(pole.rawValue)-edited.png")
        let preparedURL = directory.appending(path: "\(pole.rawValue)-prepared.png")
        phase = .retouching
        defer { if phase == .retouching { phase = .ready } }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let sourceData = try await Task.detached(priority: .userInitiated) {
            guard let maskData else {
                return try Data(contentsOf: source.sourceURL)
            }
            return try PoleRetouchService().prepareAIRetouchInput(
                from: source.sourceURL,
                maskData: maskData,
                pole: pole
            )
        }.value
        let editedData = try await OpenAIImageEditService(apiKey: apiKey).edit(
            imageData: sourceData,
            filename: "\(pole.rawValue).png",
            prompt: prompt,
            size: PoleRetouchService.plateSize
        )
        try Task.checkCancellation()
        try await Task.detached(priority: .userInitiated) {
            try editedData.write(to: editedURL, options: .atomic)
            try PoleRetouchService().prepareImportedPlate(
                from: editedURL,
                pole: pole,
                to: preparedURL
            )
        }.value
        return AIRetouchPreview(
            pole: pole,
            directoryURL: directory,
            editedURL: editedURL,
            preparedURL: preparedURL
        )
    }

    func applyAIRetouchPreview(_ preview: AIRetouchPreview) throws {
        let revision = UUID().uuidString
        let retouchDestination = retouchDirectory.appending(
            path: "\(preview.pole.rawValue)-retouch-\(revision).png"
        )
        let resultDestination = retouchDirectory.appending(
            path: "\(preview.pole.rawValue)-ai-result-\(revision).png"
        )
        try FileManager.default.createDirectory(
            at: retouchDirectory,
            withIntermediateDirectories: true
        )
        do {
            try Data(contentsOf: preview.preparedURL).write(
                to: retouchDestination,
                options: .atomic
            )
            try Data(contentsOf: preview.editedURL).write(
                to: resultDestination,
                options: .atomic
            )
        } catch {
            try? FileManager.default.removeItem(at: retouchDestination)
            try? FileManager.default.removeItem(at: resultDestination)
            throw error
        }
        let oldRetouchURL = retouchURL(for: preview.pole)
        let oldResultURL = aiRetouchResultURL(for: preview.pole)
        setRetouchURL(retouchDestination, for: preview.pole)
        setAIRetouchResultURL(resultDestination, for: preview.pole)
        if let oldRetouchURL, oldRetouchURL != retouchDestination {
            try? FileManager.default.removeItem(at: oldRetouchURL)
        }
        if let oldResultURL, oldResultURL != resultDestination {
            try? FileManager.default.removeItem(at: oldResultURL)
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
        guard let url = retouchURL(for: pole) else { return }
        let resultURL = aiRetouchResultURL(for: pole)
        setRetouchURL(nil, for: pole)
        setAIRetouchResultURL(nil, for: pole)
        try? FileManager.default.removeItem(at: url)
        if let resultURL {
            try? FileManager.default.removeItem(at: resultURL)
        }
        project.clearAIRetouchPrompt(for: pole)
        panoramaRevision += 1
    }

    func exportHTML(to destinationURL: URL, initialViewpoint: PanoramaViewpoint) {
        guard let panoramaURL = stitchedResultURL, canExportHTML else { return }
        phase = .exporting
        Task {
            do {
                try await exporter.exportHTML(
                    panoramaURL: panoramaURL,
                    nadirOverlayURL: nadirOverlayURL,
                    zenithOverlayURL: zenithOverlayURL,
                    nadirRetouchURL: nadirRetouchURL,
                    zenithRetouchURL: zenithRetouchURL,
                    title: project.title,
                    initialViewpoint: initialViewpoint,
                    to: destinationURL
                )
                phase = .ready
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

    var panoramaData: Data? { stitchedResultURL.flatMap { try? Data(contentsOf: $0) } }
    var nadirOverlayData: Data? { nadirOverlayURL.flatMap { try? Data(contentsOf: $0) } }
    var zenithOverlayData: Data? { zenithOverlayURL.flatMap { try? Data(contentsOf: $0) } }
    var nadirRetouchData: Data? { nadirRetouchURL.flatMap { try? Data(contentsOf: $0) } }
    var zenithRetouchData: Data? { zenithRetouchURL.flatMap { try? Data(contentsOf: $0) } }
    var nadirAIRetouchResultData: Data? {
        nadirAIRetouchResultURL.flatMap { try? Data(contentsOf: $0) }
    }
    var zenithAIRetouchResultData: Data? {
        zenithAIRetouchResultURL.flatMap { try? Data(contentsOf: $0) }
    }

    private var retouchDirectory: URL {
        FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/Retouch/\(project.id)",
            directoryHint: .isDirectory
        )
    }

    private func setRetouchURL(_ url: URL?, for pole: PanoramaPole) {
        if pole == .nadir { nadirRetouchURL = url }
        else { zenithRetouchURL = url }
    }

    private func setAIRetouchResultURL(_ url: URL?, for pole: PanoramaPole) {
        if pole == .nadir { nadirAIRetouchResultURL = url }
        else { zenithAIRetouchResultURL = url }
    }

    private func retainMasks(for images: [SourceImage]) {
        let ids = Set(images.map(\.id))
        maskDataByImageID = maskDataByImageID.filter { ids.contains($0.key) }
        protectedMaskDataByImageID = protectedMaskDataByImageID.filter {
            ids.contains($0.key)
        }
        maskUndoHistory = maskUndoHistory.filter { ids.contains($0.key) }
        maskRevision += 1
    }

    private func recordMaskUndo(for id: UUID) {
        var history = maskUndoHistory[id] ?? []
        history.append(MaskSnapshot(
            red: maskDataByImageID[id],
            green: protectedMaskDataByImageID[id]
        ))
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
        maskUndoHistory[id] = history
    }

    private func invalidatePanorama() {
        stitchedResultURL = nil
        nadirOverlayURL = nil
        zenithOverlayURL = nil
        nadirRetouchURL = nil
        zenithRetouchURL = nil
        nadirAIRetouchResultURL = nil
        zenithAIRetouchResultURL = nil
        lastStitchCoverage = nil
        lastStitchHoleCount = nil
        usedAlignmentCache = false
        panoramaRevision += 1
    }

    private static func restoreData(_ data: Data, filename: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/Projects",
            directoryHint: .isDirectory
        )
        let url = directory.appending(path: filename)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
