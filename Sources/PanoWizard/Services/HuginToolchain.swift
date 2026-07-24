import Foundation

struct HuginToolchain: Sendable {
    let root: URL

    var toolsDirectory: URL {
        root.appending(path: "MacOS", directoryHint: .isDirectory)
    }

    var librariesDirectory: URL {
        root.appending(path: "Libraries", directoryHint: .isDirectory)
    }

    static func live() throws -> HuginToolchain {
        let fileManager = FileManager.default
        let bundled = Bundle.main.resourceURL?
            .appending(path: "Hugin", directoryHint: .isDirectory)
        if let bundled,
           fileManager.isExecutableFile(
               atPath: bundled.appending(path: "nona").path()
           ) == false,
           fileManager.isExecutableFile(
               atPath: bundled.appending(path: "MacOS/nona").path()
           ) {
            return HuginToolchain(root: bundled)
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let development = repository
            .appending(path: "Vendor/Hugin", directoryHint: .isDirectory)
        if fileManager.isExecutableFile(
            atPath: development.appending(path: "MacOS/nona").path()
        ) {
            return HuginToolchain(root: development)
        }

        throw PanoramaEngineError.stitchingFailed(
            "Hugins verktyg saknas i appen."
        )
    }

    func run(
        _ tool: String,
        arguments: [String],
        in workDirectory: URL
    ) throws {
        let executable = toolsDirectory.appending(path: tool)
        guard FileManager.default.isExecutableFile(atPath: executable.path()) else {
            throw PanoramaEngineError.stitchingFailed(
                "Hugin-verktyget \(tool) saknas."
            )
        }

        let logURL = workDirectory.appending(
            path: "\(tool)-\(UUID().uuidString).log"
        )
        FileManager.default.createFile(atPath: logURL.path(), contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer {
            try? log.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workDirectory
        process.standardOutput = log
        process.standardError = log
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_LIBRARY_PATH"] = librariesDirectory.path()
        environment["OMP_NUM_THREADS"] = "1"
        process.environment = environment

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PanoramaEngineError.stitchingFailed(
                "\(tool) kunde inte startas: \(error.localizedDescription)"
            )
        }

        guard process.terminationStatus == 0 else {
            let data = (try? Data(contentsOf: logURL)) ?? Data()
            let output = String(decoding: data.suffix(4_000), as: UTF8.self)
            throw PanoramaEngineError.stitchingFailed(
                "\(tool) misslyckades.\n\(output)"
            )
        }
    }
}
