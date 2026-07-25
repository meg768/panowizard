import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let panoWizardProject = UTType(
        exportedAs: "se.egelberg.panowizard.project",
        conformingTo: .package
    )
}

struct PanoProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.panoWizardProject]
    }

    var project: PanoProject
    var masks: [UUID: Data]
    var panoramaData: Data?
    var nadirOverlayData: Data?

    init(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil
    ) {
        self.project = project
        self.masks = masks
        self.panoramaData = panoramaData
        self.nadirOverlayData = nadirOverlayData
    }

    init(configuration: ReadConfiguration) throws {
        guard configuration.file.isDirectory,
              let wrappers = configuration.file.fileWrappers,
              let projectData = wrappers["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        project = try decoder.decode(PanoProject.self, from: projectData)

        guard project.formatVersion == PanoProject.currentFormatVersion else {
            throw CocoaError(
                .fileReadUnsupportedScheme,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Projektformatet stöds inte av den här versionen av PanoWizard."
                ]
            )
        }

        masks = [:]
        if let maskWrappers = wrappers["masks"]?.fileWrappers {
            for (filename, wrapper) in maskWrappers {
                guard filename.hasSuffix(".png"),
                      let id = UUID(uuidString: String(filename.dropLast(4))),
                      let data = wrapper.regularFileContents else {
                    continue
                }
                masks[id] = data
            }
        }
        panoramaData = wrappers["panorama"]?
            .fileWrappers?["result.jpg"]?
            .regularFileContents
        nadirOverlayData = wrappers["panorama"]?
            .fileWrappers?["nadir-overlay.png"]?
            .regularFileContents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        var children: [String: FileWrapper] = [
            "project.json": FileWrapper(
                regularFileWithContents: try encoder.encode(project)
            )
        ]

        let maskChildren = Dictionary(uniqueKeysWithValues: masks.map { id, data in
            ("\(id.uuidString).png", FileWrapper(regularFileWithContents: data))
        })
        children["masks"] = FileWrapper(directoryWithFileWrappers: maskChildren)

        var panoramaChildren: [String: FileWrapper] = [:]
        if let panoramaData {
            panoramaChildren["result.jpg"] = FileWrapper(
                regularFileWithContents: panoramaData
            )
        }
        if let nadirOverlayData {
            panoramaChildren["nadir-overlay.png"] = FileWrapper(
                regularFileWithContents: nadirOverlayData
            )
        }
        if !panoramaChildren.isEmpty {
            children["panorama"] = FileWrapper(
                directoryWithFileWrappers: panoramaChildren
            )
        }

        return FileWrapper(directoryWithFileWrappers: children)
    }
}
