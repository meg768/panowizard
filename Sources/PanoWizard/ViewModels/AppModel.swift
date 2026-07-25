import Foundation
import Observation

enum ProjectSelection: Hashable {
    case panorama
    case source(SourceImage.ID)
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case ready
        case importing
        case stitching
        case updatingRepair
        case blendingRepair
        case failed(String)

        var message: String {
            switch self {
            case .ready:
                "Redo"
            case .importing:
                "Läser bilder och metadata…"
            case .stitching:
                "Sammanfogar panorama…"
            case .updatingRepair:
                "Uppdaterar nadirreparation…"
            case .blendingRepair:
                "Blandar nadirreparation med Enblend…"
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
    var nadirOverlayURL: URL?
    var maskDataByImageID: [UUID: Data]
    var maskRevision = 0
    var panoramaRevision = 0
    var brushDiameter: Double = 48
    var isErasingMask = false
    var sourceImageZoom = 1.0
    var isAdjustingNadir = false
    var nadirAdjustment = NadirRepairAdjustment.identity
    private var maskUndoStack: [(UUID, Data?)] = []
    private var repairRenderRevision = 0

    init(
        project: PanoProject,
        importer: any ImageImporting,
        grouper: any PanoramaGrouping,
        panoramaEngine: any PanoramaEngine,
        exporter: any PanoramaExporting,
        masks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil
    ) {
        self.project = project
        self.importer = importer
        self.grouper = grouper
        self.panoramaEngine = panoramaEngine
        self.exporter = exporter
        maskDataByImageID = masks
        nadirAdjustment = project.nadirRepairPlacement?.manualAdjustment
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
    }

    static func live(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil
    ) -> AppModel {
        AppModel(
            project: project,
            importer: ImageImportService(metadataReader: ImageMetadataReader()),
            grouper: PanoramaGroupingService(),
            panoramaEngine: HuginOpenCVPanoramaEngine(),
            exporter: FilePanoramaExporter(),
            masks: masks,
            panoramaData: panoramaData,
            nadirOverlayData: nadirOverlayData
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
        case nil:
            return stitchedResultURL ?? project.images.first?.url
        }
    }

    var selectedSourceImage: SourceImage? {
        guard case .source(let id) = selection else { return nil }
        return project.images.first { $0.id == id }
    }

    var isShowingStitchedPanorama: Bool {
        selection == .panorama && stitchedResultURL != nil
    }

    var isShowingNadirRepair: Bool {
        isShowingStitchedPanorama && nadirOverlayURL != nil
    }

    var isNadirPreviewBlended: Bool {
        project.nadirRepairPlacement?.isBlendedPreview == true
    }

    var displayedNadirAdjustment: NadirRepairAdjustment {
        isNadirPreviewBlended ? .identity : nadirAdjustment
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
            && phase != .updatingRepair
            && phase != .blendingRepair
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
            maskRevision += 1
            skippedFileCount += result.skippedFiles
            stitchedResultURL = nil
            nadirOverlayURL = nil
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
        return nil
    }

    func stitch() {
        guard let panorama, canStitch else { return }
        repairRenderRevision += 1
        phase = .stitching
        let previousPlacement = project.nadirRepairPlacement

        Task {
            do {
                let result = try await panoramaEngine.stitch(
                    panorama,
                    masks: maskDataByImageID,
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
                stitchedResultURL = result.url
                nadirOverlayURL = result.nadirRepair?.overlayURL
                var newPlacement = result.nadirRepair?.placement
                if newPlacement?.imageID == previousPlacement?.imageID {
                    newPlacement?.manualAdjustment =
                        previousPlacement?.manualAdjustment
                }
                project.nadirRepairPlacement = newPlacement
                nadirAdjustment = newPlacement?.manualAdjustment ?? .identity
                isAdjustingNadir = result.nadirRepair != nil
                if !result.rigImageLines.isEmpty {
                    project.cachedRigImageLines = Dictionary(uniqueKeysWithValues:
                        result.rigImageLines.map { ($0.key.uuidString, $0.value) }
                    )
                    project.cachedRigSignature = project.rigSignature
                }
                panoramaRevision += 1
                selection = .panorama
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
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
        maskRevision += 1
        repairRenderRevision += 1
        stitchedResultURL = nil
        nadirOverlayURL = nil
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
        maskDataByImageID[id]
    }

    func setMaskData(_ data: Data?, for id: UUID) {
        maskUndoStack.append((id, maskDataByImageID[id]))
        maskDataByImageID[id] = data
        maskRevision += 1
        if refreshNadirOverlayIfPossible(for: id) {
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

    var canUndoMask: Bool {
        !maskUndoStack.isEmpty
    }

    func undoMask() {
        guard let (id, data) = maskUndoStack.popLast() else { return }
        maskDataByImageID[id] = data
        maskRevision += 1
        if refreshNadirOverlayIfPossible(for: id) {
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

    func zoomSourceImageIn() {
        sourceImageZoom = min(sourceImageZoom * 1.25, 8)
    }

    func zoomSourceImageOut() {
        sourceImageZoom = max(sourceImageZoom / 1.25, 1)
    }

    func setNadirAdjustment(_ adjustment: NadirRepairAdjustment) {
        nadirAdjustment = adjustment
        project.setNadirRepairAdjustment(adjustment)
    }

    func resetNadirAdjustment() {
        setNadirAdjustment(.identity)
    }

    func toggleNadirAdjustment() {
        guard phase == .ready,
              let placement = project.nadirRepairPlacement else {
            return
        }
        if isAdjustingNadir {
            renderBlendedNadirPreview()
        } else if placement.isBlendedPreview {
            _ = refreshNadirOverlayIfPossible(
                for: placement.imageID,
                enterAdjustment: true
            )
        } else {
            isAdjustingNadir = true
        }
    }

    func showNadirRepairPreview() {
        guard phase == .ready else { return }
        renderBlendedNadirPreview()
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

    private func refreshNadirOverlayIfPossible(
        for imageID: UUID,
        enterAdjustment: Bool = false
    ) -> Bool {
        guard
            let repairImage = project.images.first(where: {
                $0.id == imageID
                    && $0.role == .fillOnly
                    && $0.direction == .nadir
            }),
            let placement = project.nadirRepairPlacement,
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
            path: "\(UUID().uuidString)-nadir-overlay.png"
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
                nadirOverlayURL = outputURL
                project.setNadirRepairPreviewBlended(false)
                if enterAdjustment {
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

    private func renderBlendedNadirPreview() {
        guard
            let panoramaURL = stitchedResultURL,
            let placement = project.nadirRepairPlacement,
            let repairImage = project.images.first(where: {
                $0.id == placement.imageID
                    && $0.role == .fillOnly
                    && $0.direction == .nadir
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
            path: "\(UUID().uuidString)-nadir-blended.png"
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
                        placement: placement,
                        outputURL: outputURL
                    )
                }.value
                guard revision == repairRenderRevision else { return }
                nadirOverlayURL = outputURL
                project.setNadirRepairPreviewBlended(true)
                selection = .panorama
                panoramaRevision += 1
                phase = .ready
            } catch {
                guard revision == repairRenderRevision else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
