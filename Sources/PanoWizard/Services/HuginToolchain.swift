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
               atPath: bundled.appending(path: "nona").path(percentEncoded: false)
           ) == false,
           fileManager.isExecutableFile(
               atPath: bundled.appending(path: "MacOS/nona").path(percentEncoded: false)
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
            atPath: development.appending(path: "MacOS/nona").path(percentEncoded: false)
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
        guard FileManager.default.isExecutableFile(atPath: executable.path(percentEncoded: false)) else {
            throw PanoramaEngineError.stitchingFailed(
                "Hugin-verktyget \(tool) saknas."
            )
        }

        let logURL = workDirectory.appending(
            path: "\(tool)-\(UUID().uuidString).log"
        )
        FileManager.default.createFile(atPath: logURL.path(percentEncoded: false), contents: nil)
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
        environment["DYLD_LIBRARY_PATH"] = librariesDirectory.path(percentEncoded: false)
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
            let retainedLog = FileManager.default.temporaryDirectory
                .appending(
                    path: "PanoWizard/Logs",
                    directoryHint: .isDirectory
                )
                .appending(path: "\(tool)-\(UUID().uuidString).log")
            try? FileManager.default.createDirectory(
                at: retainedLog.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: retainedLog, options: .atomic)
            throw PanoramaEngineError.stitchingFailed(
                "\(tool) misslyckades.\n\(output)\nLogg: \(retainedLog.path())"
            )
        }
    }

    func controlPointErrors(
        in project: URL,
        points: [DiagnosticControlPoint]
    ) throws -> [Double] {
        guard !points.isEmpty else { return [] }
        let executable = toolsDirectory.appending(path: "pano_trafo")
        guard FileManager.default.isExecutableFile(
            atPath: executable.path(percentEncoded: false)
        ) else {
            throw PanoramaEngineError.stitchingFailed(
                "Hugin-verktyget pano_trafo saknas."
            )
        }

        let input = points.flatMap {
            [
                "\($0.firstImage) \($0.firstX) \($0.firstY)",
                "\($0.secondImage) \($0.secondX) \($0.secondY)"
            ]
        }.joined(separator: "\n") + "\n"
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = [project.path(percentEncoded: false)]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_LIBRARY_PATH"] =
            librariesDirectory.path(percentEncoded: false)
        environment["OMP_NUM_THREADS"] = "1"
        process.environment = environment

        try process.run()
        standardInput.fileHandleForWriting.write(Data(input.utf8))
        try standardInput.fileHandleForWriting.close()
        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PanoramaEngineError.stitchingFailed(
                "pano_trafo misslyckades.\n"
                    + String(decoding: errorData, as: UTF8.self)
            )
        }

        let coordinates = String(decoding: outputData, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (Double, Double)? in
                let values = line.split(whereSeparator: \.isWhitespace)
                guard values.count == 2,
                      let x = Double(values[0]),
                      let y = Double(values[1]) else {
                    return nil
                }
                return (x, y)
            }
        guard coordinates.count == points.count * 2 else {
            throw PanoramaEngineError.stitchingFailed(
                "Hugin returnerade ofullständiga kontrollpunktsfel."
            )
        }
        let panoramaLine = try String(contentsOf: project, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("p ") }
        let panoramaTokens = panoramaLine?
            .split(whereSeparator: \.isWhitespace)
        let panoramaWidth = panoramaTokens?
            .first { $0.hasPrefix("w") }
            .flatMap { Double($0.dropFirst()) }
        let panoramaFieldOfView = panoramaTokens?
            .first { $0.hasPrefix("v") }
            .flatMap { Double($0.dropFirst()) }
        let wrapsHorizontally = panoramaWidth != nil
            && abs((panoramaFieldOfView ?? 0) - 360) < 0.001

        return points.indices.map { index in
            let first = coordinates[index * 2]
            let second = coordinates[index * 2 + 1]
            let directHorizontalDistance = abs(first.0 - second.0)
            let horizontalDistance: Double
            if wrapsHorizontally, let panoramaWidth {
                horizontalDistance = min(
                    directHorizontalDistance,
                    panoramaWidth - directHorizontalDistance
                )
            } else {
                horizontalDistance = directHorizontalDistance
            }
            return hypot(horizontalDistance, first.1 - second.1)
        }
    }

    func panoramaCoordinates(
        in project: URL,
        points: [(image: Int, point: CGPoint)]
    ) throws -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let executable = toolsDirectory.appending(path: "pano_trafo")
        let input = points.map {
            "\($0.image) \($0.point.x) \($0.point.y)"
        }.joined(separator: "\n") + "\n"
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = [project.path(percentEncoded: false)]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_LIBRARY_PATH"] =
            librariesDirectory.path(percentEncoded: false)
        environment["OMP_NUM_THREADS"] = "1"
        process.environment = environment
        try process.run()
        standardInput.fileHandleForWriting.write(Data(input.utf8))
        try standardInput.fileHandleForWriting.close()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let error = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PanoramaEngineError.stitchingFailed(
                "pano_trafo misslyckades.\n"
                    + String(decoding: error, as: UTF8.self)
            )
        }
        let result = String(decoding: output, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> CGPoint? in
                let values = line.split(whereSeparator: \.isWhitespace)
                guard values.count == 2,
                      let x = Double(values[0]),
                      let y = Double(values[1]) else { return nil }
                return CGPoint(x: x, y: y)
            }
        guard result.count == points.count else {
            throw PanoramaEngineError.stitchingFailed(
                "Alla reparationspunkter kunde inte projiceras till panoramat."
            )
        }
        return result
    }
}
