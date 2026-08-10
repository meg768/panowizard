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
    var controlPointMasks: [UUID: Data]
    var protectedMasks: [UUID: Data]
    var panoramaData: Data?
    var nadirOverlayData: Data?
    var zenithOverlayData: Data?

    init(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        controlPointMasks: [UUID: Data] = [:],
        protectedMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil,
        zenithOverlayData: Data? = nil
    ) {
        self.project = project
        self.masks = masks
        self.controlPointMasks = controlPointMasks
        self.protectedMasks = protectedMasks
        self.panoramaData = panoramaData
        self.nadirOverlayData = nadirOverlayData
        self.zenithOverlayData = zenithOverlayData
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
        controlPointMasks = [:]
        if let maskWrappers = wrappers["control-point-masks"]?.fileWrappers {
            for (filename, wrapper) in maskWrappers {
                guard filename.hasSuffix(".png"),
                      let id = UUID(uuidString: String(filename.dropLast(4))),
                      let data = wrapper.regularFileContents else {
                    continue
                }
                controlPointMasks[id] = data
            }
        }
        protectedMasks = [:]
        if let maskWrappers = wrappers["protected-masks"]?.fileWrappers {
            for (filename, wrapper) in maskWrappers {
                guard filename.hasSuffix(".png"),
                      let id = UUID(uuidString: String(filename.dropLast(4))),
                      let data = wrapper.regularFileContents else { continue }
                protectedMasks[id] = data
            }
        }
        panoramaData = wrappers["panorama"]?
            .fileWrappers?["result.jpg"]?
            .regularFileContents
        nadirOverlayData = wrappers["panorama"]?
            .fileWrappers?["nadir-overlay.png"]?
            .regularFileContents
        zenithOverlayData = wrappers["panorama"]?
            .fileWrappers?["zenith-overlay.png"]?
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
        let controlPointMaskChildren = Dictionary(
            uniqueKeysWithValues: controlPointMasks.map { id, data in
                ("\(id.uuidString).png", FileWrapper(regularFileWithContents: data))
            }
        )
        children["control-point-masks"] = FileWrapper(
            directoryWithFileWrappers: controlPointMaskChildren
        )
        children["protected-masks"] = FileWrapper(directoryWithFileWrappers:
            Dictionary(uniqueKeysWithValues: protectedMasks.map { id, data in
                ("\(id.uuidString).png", FileWrapper(regularFileWithContents: data))
            })
        )

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
        if let zenithOverlayData {
            panoramaChildren["zenith-overlay.png"] = FileWrapper(
                regularFileWithContents: zenithOverlayData
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
