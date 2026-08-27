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
    var nadirOverlayData: Data?
    var zenithOverlayData: Data?
    var nadirRetouchData: Data?
    var zenithRetouchData: Data?

    init(
        project: PanoProject = PanoProject(),
        masks: [UUID: Data] = [:],
        protectedMasks: [UUID: Data] = [:],
        panoramaData: Data? = nil,
        nadirOverlayData: Data? = nil,
        zenithOverlayData: Data? = nil,
        nadirRetouchData: Data? = nil,
        zenithRetouchData: Data? = nil
    ) {
        self.project = project
        self.masks = masks
        self.protectedMasks = protectedMasks
        self.panoramaData = panoramaData
        self.nadirOverlayData = nadirOverlayData
        self.zenithOverlayData = zenithOverlayData
        self.nadirRetouchData = nadirRetouchData
        self.zenithRetouchData = zenithRetouchData
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file, projectURL: nil)
    }

    init(contentsOf url: URL) throws {
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
        nadirRetouchData = wrappers["panorama"]?
            .fileWrappers?["nadir-retouch.png"]?
            .regularFileContents
        zenithRetouchData = wrappers["panorama"]?
            .fileWrappers?["zenith-retouch.png"]?
            .regularFileContents
        if let projectURL {
            resolveSourceImages(
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
        let storageDirectory = directoryURL
            ?? project.images.first?.url.deletingLastPathComponent()
        let storedProject = storageDirectory.map {
            projectWithRelativeSourcePaths(relativeTo: $0)
        } ?? project

        var children: [String: FileWrapper] = [
            "project.json": FileWrapper(
                regularFileWithContents: try encoder.encode(storedProject)
            )
        ]

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
        if let nadirRetouchData {
            panoramaChildren["nadir-retouch.png"] = FileWrapper(
                regularFileWithContents: nadirRetouchData
            )
        }
        if let zenithRetouchData {
            panoramaChildren["zenith-retouch.png"] = FileWrapper(
                regularFileWithContents: zenithRetouchData
            )
        }
        if !panoramaChildren.isEmpty {
            children["panorama"] = FileWrapper(
                directoryWithFileWrappers: panoramaChildren
            )
        }
        return FileWrapper(directoryWithFileWrappers: children)
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

    private mutating func resolveSourceImages(relativeTo directoryURL: URL) {
        for index in project.images.indices.reversed() {
            let storedURL = project.images[index].url
            let resolvedURL = storedURL.isFileURL
                ? storedURL.standardizedFileURL
                : directoryURL.appending(path: storedURL.path)
                    .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: resolvedURL.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue else {
                project.removeImage(at: index)
                continue
            }
            project.images[index].url = resolvedURL
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
        if var cachedLines = storedProject.cachedRigImageLines {
            for (key, line) in cachedLines {
                guard let imageID = UUID(uuidString: key),
                      let relativePath = relativePaths[imageID] else { continue }
                cachedLines[key] = Self.replacingCachedFilename(
                    relativePath,
                    in: line
                )
            }
            storedProject.cachedRigImageLines = cachedLines
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

    private static func replacingCachedFilename(
        _ filename: String,
        in line: String
    ) -> String {
        let escaped = filename
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        guard let expression = try? NSRegularExpression(
            pattern: #" n"[^"]*""#
        ), let match = expression.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        ), let range = Range(match.range, in: line) else { return line }
        var result = line
        result.replaceSubrange(range, with: " n\"\(escaped)\"")
        return result
    }
}
