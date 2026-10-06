import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let panoWizardProject = UTType(
        exportedAs: "se.egelberg.panowizard.project",
        conformingTo: .package
    )
}

struct PanoProjectDocument: FileDocument, Equatable {
    static var readableContentTypes: [UTType] {
        [.panoWizardProject]
    }

    var project: PanoProject
    var masks: [UUID: Data]
    var protectedMasks: [UUID: Data]
    var panoramaData: Data?
    var retouchPatchData: [UUID: Data]
    var aiRetouchMaskData: [UUID: Data]
    var sourceAccessBookmarks: [String: Data]

    private struct SourceAccessMetadata: Codable {
        var version = 1
        var bookmarks: [String: Data]
    }

    init(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        protectedMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        retouchPatchData: [UUID: Data] = [:],
        aiRetouchMaskData: [UUID: Data] = [:],
        sourceAccessBookmarks: [String: Data] = [:]
    ) {
        self.project = project
        self.masks = masks
        self.protectedMasks = protectedMasks
        self.panoramaData = panoramaData
        self.retouchPatchData = retouchPatchData
        self.aiRetouchMaskData = aiRetouchMaskData
        self.sourceAccessBookmarks = sourceAccessBookmarks
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file, projectURL: nil)
    }

    init(contentsOf url: URL) throws {
        try SourceFileAccess.shared.retain(url)
        try self.init(
            fileWrapper: FileWrapper(url: url, options: .immediate),
            projectURL: url
        )
    }

    private init(fileWrapper: FileWrapper, projectURL: URL?) throws {
        guard fileWrapper.isDirectory,
              let wrappers = fileWrapper.fileWrappers,
              let projectData = wrappers["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        project = try decoder.decode(PanoProject.self, from: projectData)
        sourceAccessBookmarks = [:]
        if let data = wrappers["source-access.json"]?.regularFileContents {
            let metadata = try decoder.decode(SourceAccessMetadata.self, from: data)
            guard metadata.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            sourceAccessBookmarks = SourceFileAccess.shared.restore(metadata.bookmarks)
        }

        guard project.formatVersion == PanoProject.currentFormatVersion else {
            throw CocoaError(
                .fileReadUnsupportedScheme,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This project format is not supported by this version of PanoWizard."
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
            .fileWrappers?["result.png"]?
            .regularFileContents
        retouchPatchData = Self.dataByUUID(
            in: wrappers["panorama"]?.fileWrappers?["patches"]
        )
        aiRetouchMaskData = Self.dataByUUID(
            in: wrappers["panorama"]?.fileWrappers?["patch-masks"]
        )
        if let projectURL {
            try resolveSourceImages(
                relativeTo: projectURL.deletingLastPathComponent()
            )
            let retainedImageIDs = Set(project.images.map(\.id))
            masks = masks.filter { retainedImageIDs.contains($0.key) }
            protectedMasks = protectedMasks.filter {
                retainedImageIDs.contains($0.key)
            }
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try packageFileWrapper()
    }

    func packageFileWrapper(relativeTo directoryURL: URL? = nil) throws
        -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let storageDirectory = directoryURL ?? project.images.first.flatMap {
            $0.url.isFileURL ? $0.url.deletingLastPathComponent() : nil
        }
        let storedProject = storageDirectory.map {
            projectWithRelativeSourcePaths(relativeTo: $0)
        } ?? project

        var children: [String: FileWrapper] = [
            "project.json": FileWrapper(
                regularFileWithContents: try encoder.encode(storedProject)
            )
        ]

        let bookmarks = SourceFileAccess.shared.bookmarks(
            for: project.images.map(\.url), preserving: sourceAccessBookmarks
        )
        if !bookmarks.isEmpty {
            children["source-access.json"] = FileWrapper(regularFileWithContents:
                try encoder.encode(SourceAccessMetadata(bookmarks: bookmarks))
            )
        }

        let maskChildren = Dictionary(uniqueKeysWithValues: masks.map { id, data in
            ("\(id.uuidString).png", FileWrapper(regularFileWithContents: data))
        })
        children["masks"] = FileWrapper(directoryWithFileWrappers: maskChildren)
        children["protected-masks"] = FileWrapper(directoryWithFileWrappers:
            Dictionary(uniqueKeysWithValues: protectedMasks.map { id, data in
                ("\(id.uuidString).png", FileWrapper(regularFileWithContents: data))
            })
        )

        var panoramaChildren: [String: FileWrapper] = [:]
        if let panoramaData {
            panoramaChildren["result.png"] = FileWrapper(
                regularFileWithContents: panoramaData
            )
        }
        if !retouchPatchData.isEmpty {
            panoramaChildren["patches"] = Self.fileWrapper(
                for: retouchPatchData
            )
        }
        if !aiRetouchMaskData.isEmpty {
            panoramaChildren["patch-masks"] = Self.fileWrapper(
                for: aiRetouchMaskData
            )
        }
        if !panoramaChildren.isEmpty {
            children["panorama"] = FileWrapper(
                directoryWithFileWrappers: panoramaChildren
            )
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    private static func dataByUUID(in wrapper: FileWrapper?) -> [UUID: Data] {
        guard let children = wrapper?.fileWrappers else { return [:] }
        return Dictionary(uniqueKeysWithValues: children.compactMap { name, file in
            guard name.hasSuffix(".png"),
                  let id = UUID(uuidString: String(name.dropLast(4))),
                  let data = file.regularFileContents else { return nil }
            return (id, data)
        })
    }

    private static func fileWrapper(for data: [UUID: Data]) -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: Dictionary(
            uniqueKeysWithValues: data.map { id, contents in
                ("\(id.uuidString).png", FileWrapper(
                    regularFileWithContents: contents
                ))
            }
        ))
    }

    func writeAtomically(to url: URL) throws {
        let originalURL = FileManager.default.fileExists(atPath: url.path)
            ? url
            : nil
        try packageFileWrapper(
            relativeTo: url.deletingLastPathComponent()
        ).write(
            to: url,
            options: .atomic,
            originalContentsURL: originalURL
        )
    }

    private mutating func resolveSourceImages(relativeTo directoryURL: URL) throws {
        var inaccessible: [URL] = []
        for index in project.images.indices.reversed() {
            let storedURL = project.images[index].url
            let resolvedURL = storedURL.isFileURL
                ? storedURL.standardizedFileURL
                : directoryURL.appending(path: storedURL.path)
                    .standardizedFileURL
            let fallbackURL = directoryURL.appending(
                path: storedURL.lastPathComponent
            ).standardizedFileURL
            do {
                try SourceFileAccess.shared.authorizeIfNeeded(for: resolvedURL)
                if !FileManager.default.fileExists(atPath: resolvedURL.path) {
                    try SourceFileAccess.shared.authorizeIfNeeded(for: fallbackURL)
                }
            } catch let error as SourceFileAccess.PermissionRequired {
                inaccessible.append(contentsOf: error.sourceURLs)
                continue
            }
            guard let existingURL = [resolvedURL, fallbackURL].first(where: {
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: $0.path,
                    isDirectory: &isDirectory
                ) && !isDirectory.boolValue
            }) else {
                project.removeImage(at: index)
                continue
            }
            project.images[index].url = existingURL
        }
        if !inaccessible.isEmpty {
            throw SourceFileAccess.PermissionRequired(sourceURLs:
                Array(Set(inaccessible)).sorted { $0.path < $1.path }
            )
        }
    }

    private func projectWithRelativeSourcePaths(
        relativeTo directoryURL: URL
    ) -> PanoProject {
        var storedProject = project
        let relativePaths = Dictionary(uniqueKeysWithValues:
            project.images.map { image in
                (image.id, Self.relativePath(
                    from: directoryURL,
                    to: image.url
                ))
            }
        )
        for index in storedProject.images.indices {
            let imageID = storedProject.images[index].id
            guard let relativePath = relativePaths[imageID] else { continue }
            storedProject.images[index].url = Self.relativeURL(relativePath)
        }
        return storedProject
    }

    private static func relativePath(from directoryURL: URL, to fileURL: URL)
        -> String {
        let base = directoryURL.standardizedFileURL.pathComponents
        let target = fileURL.standardizedFileURL.pathComponents
        var commonCount = 0
        while commonCount < min(base.count, target.count),
              base[commonCount] == target[commonCount] {
            commonCount += 1
        }
        let components = Array(
            repeating: "..",
            count: base.count - commonCount
        ) + target.dropFirst(commonCount)
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    private static func relativeURL(_ path: String) -> URL {
        let encoded = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map {
            String($0).addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? String($0)
        }.joined(separator: "/")
        return URL(string: encoded)!
    }

}
