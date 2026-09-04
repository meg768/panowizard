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
    private var maskUndoStack: [(MaskKind, UUID, Data?)] = []
    private var sourceMaskUndoStack: [(UUID, Data?, Data?)] = []

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
    var maskDataByImageID: [UUID: Data]
    var protectedMaskDataByImageID: [UUID: Data]
    var maskRevision = 0
    var panoramaRevision = 0
    var sourceMaskIntent = SourceMaskIntent.exclude
    var sourceMaskTool = SourceMaskTool.brush
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
        zenithRetouchData: Data? = nil
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
            panoramaEngine: TrialOpenCVPanoramaEngine(),
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
        maskUndoStack.removeAll { $0.1 == id }
        sourceMaskUndoStack.removeAll { $0.0 == id }
        maskRevision += 1
        invalidatePanorama()
        selection = project.images.isEmpty
            ? nil
            : .source(project.images[min(index, project.images.count - 1)].id)
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
        if kind == .protected {
            maskUndoStack.append((kind, id, protectedMaskDataByImageID[id]))
            protectedMaskDataByImageID[id] = data
        } else {
            maskUndoStack.append((kind, id, maskDataByImageID[id]))
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
        sourceMaskUndoStack.append((
            id, maskDataByImageID[id], protectedMaskDataByImageID[id]
        ))
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
                width: image.pixelWidth,
                height: image.pixelHeight,
                protectedArea: activeMaskKind == .protected
              ) else { return }
        setMaskData(inverted, for: image.id)
    }

    var canUndoMask: Bool {
        !sourceMaskUndoStack.isEmpty || !maskUndoStack.isEmpty
    }

    func undoMask() {
        if let (id, red, green) = sourceMaskUndoStack.popLast() {
            maskDataByImageID[id] = red
            protectedMaskDataByImageID[id] = green
        } else if let (kind, id, data) = maskUndoStack.popLast() {
            if kind == .protected {
                protectedMaskDataByImageID[id] = data
            } else {
                maskDataByImageID[id] = data
            }
        } else { return }
        maskRevision += 1
        invalidatePanorama()
    }

    var activeMaskKind: MaskKind {
        sourceMaskIntent == .protect ? .protected : .panorama
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
        let existingURL = retouchURL(for: pole)
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
                    existingRetouchURL: existingURL,
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
            try Data(contentsOf: source.sourceURL)
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
        let destination = retouchDirectory.appending(
            path: "\(preview.pole.rawValue)-retouch.png"
        )
        try FileManager.default.createDirectory(
            at: retouchDirectory,
            withIntermediateDirectories: true
        )
        try Data(contentsOf: preview.preparedURL).write(
            to: destination,
            options: .atomic
        )
        setRetouchURL(destination, for: preview.pole)
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
        setRetouchURL(nil, for: pole)
        try? FileManager.default.removeItem(at: url)
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

    private func retainMasks(for images: [SourceImage]) {
        let ids = Set(images.map(\.id))
        maskDataByImageID = maskDataByImageID.filter { ids.contains($0.key) }
        protectedMaskDataByImageID = protectedMaskDataByImageID.filter {
            ids.contains($0.key)
        }
        maskRevision += 1
    }

    private func invalidatePanorama() {
        stitchedResultURL = nil
        nadirOverlayURL = nil
        zenithOverlayURL = nil
        nadirRetouchURL = nil
        zenithRetouchURL = nil
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
