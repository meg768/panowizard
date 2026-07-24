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
        case failed(String)

        var message: String {
            switch self {
            case .ready:
                "Redo"
            case .importing:
                "Läser bilder och metadata…"
            case .stitching:
                "Sammanfogar panorama…"
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
    var maskDataByImageID: [UUID: Data]
    var maskRevision = 0
    var panoramaRevision = 0
    var brushDiameter: Double = 48
    var isErasingMask = false
    var sourceImageZoom = 1.0
    private var maskUndoStack: [(UUID, Data?)] = []

    init(
        project: PanoProject,
        importer: any ImageImporting,
        grouper: any PanoramaGrouping,
        panoramaEngine: any PanoramaEngine,
        exporter: any PanoramaExporting,
        masks: [UUID: Data] = [:],
        panoramaData: Data? = nil
    ) {
        self.project = project
        self.importer = importer
        self.grouper = grouper
        self.panoramaEngine = panoramaEngine
        self.exporter = exporter
        maskDataByImageID = masks
        selection = project.images.first.map { .source($0.id) }
        if let panoramaData {
            stitchedResultURL = Self.restorePanorama(
                panoramaData,
                projectID: project.id
            )
        }
    }

    static func live(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        panoramaData: Data? = nil
    ) -> AppModel {
        AppModel(
            project: project,
            importer: ImageImportService(metadataReader: ImageMetadataReader()),
            grouper: PanoramaGroupingService(),
            panoramaEngine: HuginOpenCVPanoramaEngine(),
            exporter: FilePanoramaExporter(),
            masks: masks,
            panoramaData: panoramaData
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

    var canStitch: Bool {
        project.images.count >= 2
            && phase != .importing
            && phase != .stitching
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
        phase = .stitching

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
        stitchedResultURL = nil

        if images.isEmpty {
            selection = nil
        } else {
            selection = .source(images[min(index, images.count - 1)].id)
        }
    }

    func setRole(_ role: SourceImage.Role, for imageID: UUID) {
        project.setRole(role, for: imageID)
        stitchedResultURL = nil
        panoramaRevision += 1
    }

    func setDirection(_ direction: SourceImage.Direction, for imageID: UUID) {
        project.setDirection(direction, for: imageID)
        stitchedResultURL = nil
        panoramaRevision += 1
    }

    func updateStitchingConfiguration(
        _ update: (inout StitchingConfiguration) -> Void
    ) {
        let previous = project.stitching
        update(&project.stitching)
        if project.stitching != previous {
            project.invalidateRigCache()
        }
        stitchedResultURL = nil
        panoramaRevision += 1
    }

    func maskData(for id: UUID) -> Data? {
        maskDataByImageID[id]
    }

    func setMaskData(_ data: Data?, for id: UUID) {
        maskUndoStack.append((id, maskDataByImageID[id]))
        maskDataByImageID[id] = data
        maskRevision += 1
        stitchedResultURL = nil
        panoramaRevision += 1
    }

    var canUndoMask: Bool {
        !maskUndoStack.isEmpty
    }

    func undoMask() {
        guard let (id, data) = maskUndoStack.popLast() else { return }
        maskDataByImageID[id] = data
        maskRevision += 1
        stitchedResultURL = nil
        panoramaRevision += 1
    }

    func zoomSourceImageIn() {
        sourceImageZoom = min(sourceImageZoom * 1.25, 8)
    }

    func zoomSourceImageOut() {
        sourceImageZoom = max(sourceImageZoom / 1.25, 1)
    }

    var panoramaData: Data? {
        guard let stitchedResultURL else { return nil }
        return try? Data(contentsOf: stitchedResultURL)
    }

    private static func restorePanorama(_ data: Data, projectID: UUID) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PanoWizard/Projects", directoryHint: .isDirectory)
        let url = directory.appending(path: "\(projectID.uuidString).jpg")
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
}
