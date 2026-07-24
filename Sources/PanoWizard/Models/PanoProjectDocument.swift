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

    init(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        panoramaData: Data? = nil
    ) {
        self.project = project
        self.masks = masks
        self.panoramaData = panoramaData
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

        if let panoramaData {
            children["panorama"] = FileWrapper(directoryWithFileWrappers: [
                "result.jpg": FileWrapper(regularFileWithContents: panoramaData)
            ])
        }

        return FileWrapper(directoryWithFileWrappers: children)
    }
}
