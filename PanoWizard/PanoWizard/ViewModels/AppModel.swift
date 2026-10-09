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
    enum SourceMaskIntent: Hashable { case exclude, protect }
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
            case .ready: "Ready"
            case .importing: "Reading images and metadata…"
            case .stitching: "Stitching panorama…"
            case .retouching: "Preparing retouch patch…"
            case .exporting: "Exporting…"
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
    var selection: ProjectSelection?
    var phase: Phase = .ready
    var isImporterPresented = false
    var skippedFileCount = 0
    var stitchedResultURL: URL?
    var retouchedPanoramaURL: URL?
    var panoramaViewpoint = PanoramaViewpoint()
    var retouchPatchURLs: [UUID: URL] = [:]
    var aiRetouchMaskDataByPatchID: [UUID: Data]
    var maskDataByImageID: [UUID: Data]
    var protectedMaskDataByImageID: [UUID: Data]
    var maskRevision = 0
    var panoramaRevision = 0
    var aiRetouchMaskRevision = 0
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
        retouchPatchData: [UUID: Data] = [:],
        aiRetouchMaskData: [UUID: Data] = [:]
    ) {
        self.project = project
        self.importer = importer
        self.grouper = grouper
        self.panoramaEngine = panoramaEngine
        self.exporter = exporter
        maskDataByImageID = masks
        protectedMaskDataByImageID = protectedMasks
        aiRetouchMaskDataByPatchID = aiRetouchMaskData
        panoramaViewpoint = project.previewViewpoint ?? PanoramaViewpoint()
        stitchedResultURL = panoramaData.flatMap {
            Self.restoreData($0, filename: "\(project.id)-panorama.png")
        }
        selection = stitchedResultURL != nil
            ? .panorama
            : project.images.first.map { .source($0.id) }
        retouchPatchURLs = Dictionary(uniqueKeysWithValues:
            retouchPatchData.compactMap { id, data in
                Self.restoreData(
                    data,
                    filename: "\(project.id)-retouch-patch-\(id).png"
                ).map { (id, $0) }
            }
        )
        try? rebuildRetouchedPanorama()
    }

    static func live(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        protectedMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        retouchPatchData: [UUID: Data] = [:],
        aiRetouchMaskData: [UUID: Data] = [:]
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
            retouchPatchData: retouchPatchData,
            aiRetouchMaskData: aiRetouchMaskData
        )
    }

    var panorama: PanoramaSet? { project.images.isEmpty ? nil : project.panorama }
    var sourceDirectoryURL: URL? { project.images.first?.url.deletingLastPathComponent() }
    var currentPanoramaURL: URL? { retouchedPanoramaURL ?? stitchedResultURL }
    var panoramaAdjustments: PanoramaAdjustments { project.panoramaAdjustments }

    var selectedPreviewURL: URL? {
        switch selection {
        case .panorama: currentPanoramaURL
        case .source(let id):
            project.images.first { $0.id == id }?.url ?? project.images.first?.url
        case .retouch, .export: nil
        case nil: currentPanoramaURL ?? project.images.first?.url
        }
    }

    var selectedSourceImage: SourceImage? {
        guard case .source(let id) = selection else { return nil }
        return project.images.first { $0.id == id }
    }

    var isShowingStitchedPanorama: Bool {
        selection == .panorama && currentPanoramaURL != nil
    }

    var canStitch: Bool {
        project.images.filter(\.isEnabled).count >= 2 && phase == .ready
    }

    var canCancelStitch: Bool { phase == .stitching }
    var canExportHTML: Bool { currentPanoramaURL != nil && phase == .ready }

    func setPanoramaViewpoint(_ viewpoint: PanoramaViewpoint) {
        guard panoramaViewpoint != viewpoint else { return }
        panoramaViewpoint = viewpoint
        project.previewViewpoint = viewpoint
    }

    func setPanoramaAdjustment(
        _ keyPath: WritableKeyPath<PanoramaAdjustments, Double>,
        to value: Double
    ) {
        var adjustments = panoramaAdjustments
        adjustments[keyPath: keyPath] = value
        project.setPanoramaAdjustments(adjustments)
    }

    func resetPanoramaAdjustment(
        _ keyPath: WritableKeyPath<PanoramaAdjustments, Double>
    ) {
        setPanoramaAdjustment(keyPath, to: 0)
    }

    func resetPanoramaAdjustments() {
        project.setPanoramaAdjustments(.neutral)
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

    func removeAllSourceImages() {
        guard !project.images.isEmpty else { return }
        cancelStitch()
        project.replaceImages([])
        maskDataByImageID.removeAll()
        protectedMaskDataByImageID.removeAll()
        maskUndoHistory.removeAll()
        maskRevision += 1
        invalidatePanorama()
        selection = nil
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

    func selectAndToggleSourceImageEnabled(_ id: SourceImage.ID) {
        guard project.images.contains(where: { $0.id == id }) else { return }
        selection = .source(id)
        toggleSourceImageEnabled(id)
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
        stitchStage = "Preparing panorama engine…"
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
                clearRetouchPatches()
                project.setPanoramaAdjustments(.neutral)
                lastStitchCoverage = result.coveragePercent
                lastStitchHoleCount = result.holeCount
                usedAlignmentCache = result.usedAlignmentCache
                stitchProgress = 1
                stitchStage = "Panorama complete"
                selection = .panorama
                panoramaRevision += 1
                phase = .ready
            } catch is CancellationError {
                guard stitchOperationID == operationID else { return }
                phase = .ready
                stitchStage = "Panorama creation cancelled"
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
        stitchStage = "Cancelling panorama creation…"
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
        guard let id = selectedSourceImage?.id else { return false }
        return maskUndoHistory[id]?.isEmpty == false
    }

    func undoMask() {
        guard let id = selectedSourceImage?.id,
              let snapshot = maskUndoHistory[id]?.popLast() else { return }
        maskDataByImageID[id] = snapshot.red
        protectedMaskDataByImageID[id] = snapshot.green
        maskRevision += 1
        invalidatePanorama()
    }

    var activeMaskKind: MaskKind {
        sourceMaskIntent == .protect ? .protected : .panorama
    }

    var retouchPatches: [RetouchPatch] { project.retouchPatches }

    func createRetouchPatchSource(
        at viewpoint: PanoramaViewpoint,
        replacing existingPatch: RetouchPatch? = nil
    ) async throws -> AIRetouchSource {
        guard let stitchedResultURL else { throw AIRetouchError.panoramaUnavailable }
        let basePanoramaURL: URL
        let sourcePatches: [(RetouchPatch, URL)]
        if let existingPatch {
            guard let index = project.retouchPatches.firstIndex(where: {
                $0.id == existingPatch.id
            }) else { throw RetouchPatchError.patchUnavailable }
            basePanoramaURL = stitchedResultURL
            sourcePatches = project.retouchPatches[..<index].compactMap { patch in
                retouchPatchURLs[patch.id].map { (patch, $0) }
            }
        } else {
            basePanoramaURL = currentPanoramaURL ?? stitchedResultURL
            sourcePatches = []
        }
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/RetouchPatch/\(project.id)/\(UUID())",
            directoryHint: .isDirectory
        )
        let sourceURL = directory.appending(path: "source.png")
        let compositeURL = directory.appending(path: "source-panorama.png")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            try await Task.detached(priority: .userInitiated) {
                let panoramaURL: URL
                if sourcePatches.contains(where: { $0.0.isEnabled }) {
                    try RetouchPatchService().render(
                        panoramaURL: basePanoramaURL,
                        patches: sourcePatches,
                        to: compositeURL
                    )
                    panoramaURL = compositeURL
                } else {
                    panoramaURL = basePanoramaURL
                }
                try RetouchPatchService().exportPatch(
                    panoramaURL: panoramaURL,
                    viewpoint: viewpoint,
                    to: sourceURL
                )
            }.value
            return AIRetouchSource(
                viewpoint: viewpoint,
                directoryURL: directory,
                sourceURL: sourceURL
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func createExistingRetouchPatchPreview(
        source: AIRetouchSource,
        patch: RetouchPatch
    ) async throws -> URL {
        guard let patchURL = retouchPatchURLs[patch.id] else {
            throw RetouchPatchError.patchUnavailable
        }
        let destination = source.directoryURL.appending(
            path: "existing-preview.png"
        )
        try await Task.detached(priority: .userInitiated) {
            try RetouchPatchService().compositePatch(
                backgroundURL: source.sourceURL,
                patchURL: patchURL,
                to: destination
            )
        }.value
        return destination
    }

    func createAIRetouchPreview(
        source: AIRetouchSource,
        maskData: Data?,
        prompt: String,
        apiKey: String
    ) async throws -> AIRetouchPreview {
        guard stitchedResultURL != nil,
              phase == .ready,
              FileManager.default.fileExists(atPath: source.sourceURL.path)
        else { throw AIRetouchError.panoramaUnavailable }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw AIRetouchError.emptyPrompt }
        guard let maskData else { throw AIRetouchError.missingMask }
        let directory = source.directoryURL.appending(
            path: "Previews/\(UUID())",
            directoryHint: .isDirectory
        )
        let editedURL = directory.appending(path: "edited.png")
        let preparedURL = directory.appending(path: "prepared.png")
        let compositedURL = directory.appending(path: "composited.png")
        phase = .retouching
        defer { if phase == .retouching { phase = .ready } }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let sourceData = try await Task.detached(priority: .userInitiated) {
            try RetouchPatchService().prepareAIRetouchInput(
                from: source.sourceURL,
                maskData: maskData
            )
        }.value
        let editedData = try await OpenAIImageEditService(apiKey: apiKey).edit(
            imageData: sourceData,
            filename: "patch.png",
            prompt: prompt,
            size: RetouchPatchService.patchSize
        )
        try Task.checkCancellation()
        try await Task.detached(priority: .userInitiated) {
            try editedData.write(to: editedURL, options: .atomic)
            try RetouchPatchService().prepareAIRetouchPatch(
                originalURL: source.sourceURL,
                editedURL: editedURL,
                maskData: maskData,
                overlayURL: preparedURL,
                previewURL: compositedURL
            )
        }.value
        return AIRetouchPreview(
            viewpoint: source.viewpoint,
            directoryURL: directory,
            editedURL: editedURL,
            preparedURL: preparedURL,
            compositedURL: compositedURL
        )
    }

    func applyAIRetouchPreview(
        _ preview: AIRetouchPreview,
        prompt: String,
        maskData: Data,
        replacing existingPatch: RetouchPatch? = nil
    ) throws {
        let patch = RetouchPatch(
            id: existingPatch?.id ?? UUID(),
            kind: .ai,
            viewpoint: preview.viewpoint,
            isEnabled: existingPatch?.isEnabled ?? true,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try storeRetouchPatch(
            patch,
            imageURL: preview.preparedURL,
            maskData: maskData,
            replacing: existingPatch?.id
        )
    }

    func applyManualRetouchPatch(
        from importedURL: URL,
        viewpoint: PanoramaViewpoint,
        replacing existingPatch: RetouchPatch? = nil
    ) throws {
        let patch = RetouchPatch(
            id: existingPatch?.id ?? UUID(),
            kind: .manual,
            viewpoint: viewpoint,
            isEnabled: existingPatch?.isEnabled ?? true
        )
        try storeRetouchPatch(
            patch,
            imageURL: importedURL,
            maskData: nil,
            replacing: existingPatch?.id
        )
    }

    func discardRetouchPatchSource(_ source: AIRetouchSource) {
        try? FileManager.default.removeItem(at: source.directoryURL)
    }

    func discardAIRetouchPreview(_ preview: AIRetouchPreview) {
        try? FileManager.default.removeItem(at: preview.directoryURL)
    }

    func toggleRetouchPatch(_ id: UUID) {
        guard let index = project.retouchPatches.firstIndex(where: {
            $0.id == id
        }) else { return }
        let previousPatches = project.retouchPatches
        var updatedPatches = previousPatches
        updatedPatches[index].isEnabled.toggle()
        project.setRetouchPatches(updatedPatches)
        do {
            try rebuildRetouchedPanorama()
            panoramaRevision += 1
        } catch {
            project.setRetouchPatches(previousPatches)
            phase = .failed(error.localizedDescription)
        }
    }

    func removeRetouchPatch(_ id: UUID) {
        guard project.retouchPatches.contains(where: { $0.id == id }) else {
            return
        }
        let previousPatches = project.retouchPatches
        project.setRetouchPatches(previousPatches.filter { $0.id != id })
        let removedURL = retouchPatchURLs.removeValue(forKey: id)
        let removedMask = aiRetouchMaskDataByPatchID.removeValue(forKey: id)
        do {
            try rebuildRetouchedPanorama()
            if let removedURL { try? FileManager.default.removeItem(at: removedURL) }
            panoramaRevision += 1
        } catch {
            project.setRetouchPatches(previousPatches)
            if let removedURL { retouchPatchURLs[id] = removedURL }
            if let removedMask { aiRetouchMaskDataByPatchID[id] = removedMask }
            phase = .failed(error.localizedDescription)
        }
    }

    func showRetouchPatch(_ patch: RetouchPatch) {
        setPanoramaViewpoint(patch.viewpoint)
        selection = .panorama
    }

    func exportHTML(to destinationURL: URL, initialViewpoint: PanoramaViewpoint) {
        guard let panoramaURL = currentPanoramaURL, canExportHTML else { return }
        phase = .exporting
        Task {
            do {
                try await exporter.exportHTML(
                    panoramaURL: panoramaURL,
                    adjustments: panoramaAdjustments,
                    title: project.title,
                    initialViewpoint: initialViewpoint,
                    to: destinationURL
                )
                phase = .ready
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

    var panoramaData: Data? { stitchedResultURL.flatMap { try? Data(contentsOf: $0) } }
    var retouchPatchData: [UUID: Data] {
        Dictionary(uniqueKeysWithValues: retouchPatchURLs.compactMap { id, url in
            (try? Data(contentsOf: url)).map { (id, $0) }
        })
    }

    private func storeRetouchPatch(
        _ patch: RetouchPatch,
        imageURL: URL,
        maskData: Data?,
        replacing patchID: RetouchPatch.ID?
    ) throws {
        let destination = retouchDirectory.appending(
            path: "patch-\(patch.id)-\(UUID()).png"
        )
        try FileManager.default.createDirectory(
            at: retouchDirectory,
            withIntermediateDirectories: true
        )
        try RetouchPatchService().prepareImportedPatch(
            from: imageURL,
            to: destination
        )
        let oldPatches = project.retouchPatches
        var updatedPatches = oldPatches
        if let patchID {
            guard let index = oldPatches.firstIndex(where: {
                $0.id == patchID && $0.kind == patch.kind
            }) else {
                try? FileManager.default.removeItem(at: destination)
                throw RetouchPatchError.patchUnavailable
            }
            updatedPatches[index] = patch
        } else {
            updatedPatches.append(patch)
        }

        let oldURL = retouchPatchURLs[patch.id]
        let oldMaskData = aiRetouchMaskDataByPatchID[patch.id]
        project.setRetouchPatches(updatedPatches)
        retouchPatchURLs[patch.id] = destination
        aiRetouchMaskDataByPatchID[patch.id] = maskData
        do {
            try rebuildRetouchedPanorama()
            if let oldURL, oldURL != destination {
                try? FileManager.default.removeItem(at: oldURL)
            }
            panoramaRevision += 1
        } catch {
            project.setRetouchPatches(oldPatches)
            retouchPatchURLs[patch.id] = oldURL
            aiRetouchMaskDataByPatchID[patch.id] = oldMaskData
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private var retouchDirectory: URL {
        FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard/Retouch/\(project.id)",
            directoryHint: .isDirectory
        )
    }

    private func rebuildRetouchedPanorama() throws {
        guard let stitchedResultURL else {
            retouchedPanoramaURL = nil
            return
        }
        let active = project.retouchPatches.compactMap { patch in
            retouchPatchURLs[patch.id].map { (patch, $0) }
        }
        guard active.contains(where: { $0.0.isEnabled }) else {
            if let retouchedPanoramaURL {
                try? FileManager.default.removeItem(at: retouchedPanoramaURL)
            }
            retouchedPanoramaURL = nil
            return
        }
        try FileManager.default.createDirectory(
            at: retouchDirectory,
            withIntermediateDirectories: true
        )
        let destination = retouchDirectory.appending(
            path: "composite-\(UUID().uuidString).png"
        )
        try RetouchPatchService().render(
            panoramaURL: stitchedResultURL,
            patches: active,
            to: destination
        )
        let oldURL = retouchedPanoramaURL
        retouchedPanoramaURL = destination
        if let oldURL, oldURL != destination {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    private func clearRetouchPatches() {
        let urls = Array(retouchPatchURLs.values)
        if let retouchedPanoramaURL {
            try? FileManager.default.removeItem(at: retouchedPanoramaURL)
        }
        retouchedPanoramaURL = nil
        retouchPatchURLs = [:]
        aiRetouchMaskDataByPatchID = [:]
        project.setRetouchPatches([])
        for url in urls { try? FileManager.default.removeItem(at: url) }
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
        clearRetouchPatches()
        project.setPanoramaAdjustments(.neutral)
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
