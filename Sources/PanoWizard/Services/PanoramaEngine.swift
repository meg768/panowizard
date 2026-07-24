import Foundation
import OpenCVBridge

protocol PanoramaEngine: Sendable {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult
}

struct PanoramaStitchResult: Sendable {
    let url: URL
    let rigImageLines: [UUID: String]
}

enum PanoramaEngineError: LocalizedError {
    case insufficientImages
    case stitchingFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientImages:
            "Minst två bilder krävs för sammanfogning."
        case .stitchingFailed(let message):
            message
        }
    }
}

struct OpenCVPanoramaEngine: PanoramaEngine {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult {
        guard panorama.images.count >= 2 else {
            throw PanoramaEngineError.insufficientImages
        }

        let inputPaths = panorama.images.map { $0.url.path(percentEncoded: false) }
        let fisheyeInput = panorama.images.contains { $0.lens.kind == .fisheye }
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "PanoWizard", directoryHint: .isDirectory)
            .appending(path: "\(panorama.id.uuidString).jpg")

        return try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let mutablePointers = inputPaths.map { strdup($0) }
            defer {
                mutablePointers.forEach { free($0) }
            }
            let pointers: [UnsafePointer<CChar>?] = mutablePointers.map {
                guard let pointer = $0 else { return nil }
                return UnsafePointer<CChar>(pointer)
            }

            var errorPointer: UnsafeMutablePointer<CChar>?
            let succeeded = pointers.withUnsafeBufferPointer { buffer in
                PWStitchImages(
                    buffer.baseAddress,
                    Int32(buffer.count),
                    fisheyeInput,
                    outputURL.path(percentEncoded: false),
                    &errorPointer
                )
            }

            defer {
                if let errorPointer {
                    PWFreeString(errorPointer)
                }
            }

            guard succeeded else {
                let message = errorPointer.map { String(cString: $0) }
                    ?? "OpenCV kunde inte skapa panoramat."
                throw PanoramaEngineError.stitchingFailed(message)
            }
            return PanoramaStitchResult(url: outputURL, rigImageLines: [:])
        }.value
    }
}

struct AdaptivePanoramaEngine: PanoramaEngine {
    let openCV: OpenCVPanoramaEngine
    let hugin: HuginPanoramaEngine

    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult {
        if configuration.engine == .openCV {
            return try await openCV.stitch(
                panorama,
                masks: masks,
                configuration: configuration,
                cachedRigImageLines: cachedRigImageLines
            )
        }
        let explicitlyUsesHugin = configuration.engine == .hugin
            || configuration.lensProfile != .automatic
            || panorama.images.contains { $0.direction != .horizontal }
        if explicitlyUsesHugin || isFullSphereSet(panorama) || !masks.isEmpty {
            return try await hugin.stitch(
                panorama,
                masks: masks,
                configuration: configuration,
                cachedRigImageLines: cachedRigImageLines
            )
        }
        return try await openCV.stitch(
            panorama,
            masks: masks,
            configuration: configuration,
            cachedRigImageLines: cachedRigImageLines
        )
    }

    private func isFullSphereSet(_ panorama: PanoramaSet) -> Bool {
        if panorama.images.contains(where: { $0.lens.kind == .fisheye }) {
            return true
        }

        let portraitImages = panorama.images.filter {
            $0.pixelHeight > $0.pixelWidth
        }
        return panorama.images.count >= 6
            && portraitImages.count == panorama.images.count
    }
}

struct HuginPanoramaEngine: PanoramaEngine {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult {
        let repairImages = panorama.images.filter { $0.role == .fillOnly }
        let panorama = PanoramaSet(
            id: panorama.id,
            images: panorama.images.filter { $0.role == .alignment }
        )
        guard panorama.images.count >= 2 else {
            throw PanoramaEngineError.insufficientImages
        }
        let paths = panorama.images.map { $0.url.path(percentEncoded: false) }
        let fillOnlyIndices = Set<Int>()
        let toolsDirectory = Self.toolsDirectory()
        let workDirectory = FileManager.default.temporaryDirectory
            .appending(path: "PanoWizard/Hugin/\(panorama.id.uuidString)", directoryHint: .isDirectory)

        return try await Task.detached(priority: .userInitiated) {
            if FileManager.default.fileExists(atPath: workDirectory.path()) {
                try FileManager.default.removeItem(at: workDirectory)
            }
            try FileManager.default.createDirectory(
                at: workDirectory,
                withIntermediateDirectories: true
            )

            let base = workDirectory.appending(path: "base.pto")
            let controlPoints = workDirectory.appending(path: "control-points.pto")
            let cleaned = workDirectory.appending(path: "cleaned.pto")
            let rigInput = workDirectory.appending(path: "rig-input.pto")
            let rigOptimized = workDirectory.appending(path: "rig-optimized.pto")
            let repairInput = workDirectory.appending(path: "repair-input.pto")
            let geometryOptimized = workDirectory.appending(path: "geometry.pto")
            let optimized = workDirectory.appending(path: "optimized.pto")
            let final = workDirectory.appending(path: "final.pto")
            let renderProject = workDirectory.appending(path: "render.pto")
            let layerPrefix = workDirectory.appending(path: "layer")
            let result = workDirectory.appending(path: "panorama.jpg")

            try Self.run(
                "pto_gen",
                arguments: [
                    "-p", Self.huginLensProjection(
                        configuration,
                        panorama: panorama
                    ),
                    "-f", String(Self.horizontalFieldOfView(
                        configuration,
                        panorama: panorama
                    )),
                    "-o", base.path()
                ] + paths,
                toolsDirectory: toolsDirectory,
                workDirectory: workDirectory
            )
            let seeded = workDirectory.appending(path: "seeded.pto")
            try Self.seedImageDirections(
                from: base,
                to: seeded,
                images: panorama.images
            )
            let hasCompleteRigCache = panorama.images
                .filter { $0.role == .alignment }
                .allSatisfy { cachedRigImageLines[$0.id] != nil }
            if hasCompleteRigCache {
                try Self.applyCachedRigImageLines(
                    to: seeded,
                    images: panorama.images,
                    cachedLines: cachedRigImageLines
                )
            }
            try Self.run(
                "cpfind",
                arguments: [
                    "--prealigned",
                    "--ncores=1",
                    "--ransacmode=rpy"
                ] + [
                    "-o", controlPoints.path(),
                    seeded.path()
                ],
                toolsDirectory: toolsDirectory,
                workDirectory: workDirectory
            )
            try Self.run(
                "cpclean",
                arguments: ["-o", cleaned.path(), controlPoints.path()],
                toolsDirectory: toolsDirectory,
                workDirectory: workDirectory
            )
            var rigGeometrySource = optimized
            if !fillOnlyIndices.isEmpty {
                try Self.makeRigOptimizationProject(
                    from: cleaned,
                    to: rigInput,
                    imageCount: panorama.images.count,
                    fillOnlyIndices: fillOnlyIndices
                )
                let lockedRig: URL
                if hasCompleteRigCache {
                    lockedRig = rigInput
                } else {
                    try Self.run(
                        "autooptimiser",
                        arguments: [
                            "-n", "-l",
                            "-o", rigOptimized.path(),
                            rigInput.path()
                        ],
                        toolsDirectory: toolsDirectory,
                        workDirectory: workDirectory
                    )
                    lockedRig = rigOptimized
                }
                rigGeometrySource = lockedRig
                try Self.makeFillImageOptimizationProject(
                    rigProject: lockedRig,
                    controlPointProject: cleaned,
                    output: repairInput,
                    fillOnlyIndices: fillOnlyIndices
                )
                try Self.run(
                    "autooptimiser",
                    arguments: [
                        "-n",
                        "-o", geometryOptimized.path(),
                        repairInput.path()
                    ],
                    toolsDirectory: toolsDirectory,
                    workDirectory: workDirectory
                )
                try Self.run(
                    "autooptimiser",
                    arguments: [
                        "-s",
                        "-o", optimized.path(),
                        geometryOptimized.path()
                    ],
                    toolsDirectory: toolsDirectory,
                    workDirectory: workDirectory
                )
            } else {
                if hasCompleteRigCache {
                    try FileManager.default.copyItem(
                        at: cleaned,
                        to: optimized
                    )
                } else {
                    try Self.run(
                        "autooptimiser",
                        arguments: [
                            "-a", "-l", "-s",
                            "-o", optimized.path(),
                            cleaned.path()
                        ],
                        toolsDirectory: toolsDirectory,
                        workDirectory: workDirectory
                    )
                }
                rigGeometrySource = optimized
            }
            try Self.run(
                "pano_modify",
                arguments: [
                    "-o", final.path(),
                    "-p", "2",
                    "--fov=360x180",
                    "--canvas=4000x2000",
                    "--blender=ENBLEND",
                    "--ldr-file=JPG",
                    "--ldr-compression=92",
                    optimized.path()
                ],
                toolsDirectory: toolsDirectory,
                workDirectory: workDirectory
            )
            try Self.makeRenderProject(
                from: final,
                to: renderProject,
                panorama: panorama,
                masks: masks,
                workDirectory: workDirectory
            )

            try Self.renderAndBlend(
                project: renderProject,
                layerPrefix: layerPrefix,
                result: result,
                fillOnlyIndices: fillOnlyIndices,
                toolsDirectory: toolsDirectory,
                workDirectory: workDirectory
            )

            guard FileManager.default.fileExists(atPath: result.path()) else {
                throw PanoramaEngineError.stitchingFailed(
                    "Hugin skapade ingen panoramabild."
                )
            }
            var repairedResult = result
            for (repairIndex, image) in repairImages.enumerated() {
                guard let mask = masks[image.id] else { continue }
                let maskURL = workDirectory.appending(path: "repair-\(repairIndex)-mask.png")
                let outputURL = workDirectory.appending(path: "repair-\(repairIndex).jpg")
                try mask.write(to: maskURL, options: .atomic)
                try Self.applyRepair(
                    panorama: repairedResult,
                    image: image.url,
                    mask: maskURL,
                    output: outputURL
                )
                repairedResult = outputURL
            }
            return PanoramaStitchResult(
                url: repairedResult,
                rigImageLines: try Self.rigImageLines(
                    from: rigGeometrySource,
                    images: panorama.images
                )
            )
        }.value
    }

    private static func applyRepair(
        panorama: URL,
        image: URL,
        mask: URL,
        output: URL
    ) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let succeeded = PWApplyPanoramaRepair(
            panorama.path(),
            image.path(),
            mask.path(),
            output.path(),
            &errorPointer
        )
        defer {
            if let errorPointer {
                PWFreeString(errorPointer)
            }
        }
        guard succeeded else {
            let message = errorPointer.map { String(cString: $0) }
                ?? "Utfyllnadsbilden kunde inte registreras lokalt."
            throw PanoramaEngineError.stitchingFailed(message)
        }
    }

    static func applyCachedRigImageLines(
        to project: URL,
        images: [SourceImage],
        cachedLines: [UUID: String]
    ) throws {
        let source = try String(contentsOf: project, encoding: .utf8)
        var imageIndex = 0
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { substring -> String in
                defer {
                    if substring.hasPrefix("i ") { imageIndex += 1 }
                }
                guard substring.hasPrefix("i "),
                      imageIndex < images.count,
                      images[imageIndex].role == .alignment,
                      let cached = cachedLines[images[imageIndex].id] else {
                    return String(substring)
                }
                return cached
            }
        try lines.joined(separator: "\n").write(
            to: project,
            atomically: true,
            encoding: .utf8
        )
    }

    static func rigImageLines(
        from project: URL,
        images: [SourceImage]
    ) throws -> [UUID: String] {
        let lines = try String(contentsOf: project, encoding: .utf8)
            .split(separator: "\n")
            .filter { $0.hasPrefix("i ") }
            .map(String.init)
        return Dictionary(uniqueKeysWithValues: images.enumerated().compactMap {
            index, image in
            guard image.role == .alignment, index < lines.count else { return nil }
            return (image.id, lines[index])
        })
    }

    private static func renderAndBlend(
        project: URL,
        layerPrefix: URL,
        result: URL,
        fillOnlyIndices: Set<Int>,
        toolsDirectory: URL,
        workDirectory: URL
    ) throws {
        try renderLayers(
            project: project,
            layerPrefix: layerPrefix,
            toolsDirectory: toolsDirectory,
            workDirectory: workDirectory
        )
        let renderedLayers = try layers(
            in: workDirectory,
            prefix: layerPrefix.lastPathComponent
        )
        let rigLayers = renderedLayers.enumerated().compactMap { index, layer in
            fillOnlyIndices.contains(index) ? nil : layer
        }
        let arguments = [
            "-f", "4000x2000+0+0",
            "--wrap=horizontal",
            "--compression=92",
            "--output=\(result.path())"
        ] + rigLayers.map(\.path)
        do {
            try run(
                "enblend",
                arguments: arguments,
                toolsDirectory: toolsDirectory,
                workDirectory: workDirectory
            )
        } catch {
            // Some heavily hand-painted masks create degenerate seam contours.
            // Enblend can still combine those layers safely without seam optimization.
            try run(
                "enblend",
                arguments: ["--no-optimize"] + arguments,
                toolsDirectory: toolsDirectory,
                workDirectory: workDirectory
            )
        }
    }

    private static func renderLayers(
        project: URL,
        layerPrefix: URL,
        toolsDirectory: URL,
        workDirectory: URL
    ) throws {
        try run(
            "nona",
            arguments: [
                "-r", "ldr",
                "-m", "TIFF_m",
                "-o", layerPrefix.path(),
                project.path()
            ],
            toolsDirectory: toolsDirectory,
            workDirectory: workDirectory
        )
    }

    private static func layers(
        in workDirectory: URL,
        prefix: String
    ) throws -> [URL] {
        let renderedLayers = try FileManager.default.contentsOfDirectory(
            at: workDirectory,
            includingPropertiesForKeys: nil
        )
            .filter {
                $0.lastPathComponent.hasPrefix(prefix)
                    && ["tif", "tiff"].contains($0.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !renderedLayers.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "Hugin skapade inga bildlager."
            )
        }
        return renderedLayers
    }

    private static func makeRenderProject(
        from sourceProject: URL,
        to destinationProject: URL,
        panorama: PanoramaSet,
        masks: [UUID: Data],
        workDirectory: URL
    ) throws {
        var replacementPaths: [Int: String] = [:]
        for (index, image) in panorama.images.enumerated() {
            guard let mask = masks[image.id] else { continue }
            let destination = workDirectory.appending(path: "masked-\(index).tif")
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: mask,
                destinationURL: destination
            )
            replacementPaths[index] = destination.path()
        }

        let source = try String(contentsOf: sourceProject, encoding: .utf8)
        var imageIndex = 0
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { substring -> String in
            var line = String(substring)
            defer {
                if line.hasPrefix("i ") { imageIndex += 1 }
            }
            guard line.hasPrefix("i "),
                  let replacement = replacementPaths[imageIndex],
                  let nameRange = line.range(
                    of: #" n"[^"]*""#,
                    options: .regularExpression
                  ) else {
                return line
            }
            let escaped = replacement
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            line.replaceSubrange(nameRange, with: " n\"\(escaped)\"")
            return line
        }
        try lines.joined(separator: "\n").write(
            to: destinationProject,
            atomically: true,
            encoding: .utf8
        )
    }

    static func seedImageDirections(
        from sourceProject: URL,
        to destinationProject: URL,
        images: [SourceImage]
    ) throws {
        let source = try String(contentsOf: sourceProject, encoding: .utf8)
        let horizontalIndices = images.indices.filter {
            images[$0].direction == .horizontal
                && images[$0].role == .alignment
        }
        let yawByIndex = Dictionary(uniqueKeysWithValues: horizontalIndices.enumerated().map {
            offset, imageIndex in
            (imageIndex, Double(offset) * 360 / Double(max(horizontalIndices.count, 1)))
        })
        var imageIndex = 0
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { substring -> String in
            let line = String(substring)
            guard line.hasPrefix("i "), imageIndex < images.count else {
                return line
            }
            var tokens = line.split(separator: " ").map(String.init)
            let image = images[imageIndex]
            let pitch: Double = switch image.direction {
            case .horizontal: 0
            case .zenith: 90
            case .nadir: -90
            }
            tokens = replacingParameter("y", value: yawByIndex[imageIndex] ?? 0, in: tokens)
            tokens = replacingParameter("p", value: pitch, in: tokens)
            imageIndex += 1
            return tokens.joined(separator: " ")
        }
        try lines.joined(separator: "\n").write(
            to: destinationProject,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func huginLensProjection(
        _ configuration: StitchingConfiguration,
        panorama: PanoramaSet
    ) -> String {
        switch configuration.lensProfile {
        case .sigma8DX:
            return "3"
        case .nikon105DX:
            return "3"
        case .custom:
            return panorama.images.contains { $0.lens.kind == .fisheye } ? "3" : "0"
        case .automatic:
            if panorama.images.contains(where: { Self.isSigma8($0.lens) }) {
                return "2"
            }
            return panorama.images.contains { $0.lens.kind == .fisheye } ? "3" : "0"
        }
    }

    private static func horizontalFieldOfView(
        _ configuration: StitchingConfiguration,
        panorama: PanoramaSet
    ) -> Double {
        if let value = configuration.lensProfile.defaultHorizontalFieldOfView {
            return value
        }
        if configuration.lensProfile == .automatic {
            if panorama.images.contains(where: { isSigma8($0.lens) }) {
                return 100
            }
            if panorama.images.contains(where: { isNikon105($0.lens) }) {
                return 100
            }
        }
        return configuration.inputHorizontalFieldOfView
    }

    private static func isSigma8(_ lens: LensDescription) -> Bool {
        lens.model?.localizedCaseInsensitiveContains("sigma") == true
            && (lens.model?.contains("8") == true)
    }

    private static func isNikon105(_ lens: LensDescription) -> Bool {
        let model = lens.model?.lowercased() ?? ""
        return (model.contains("nikon") || model.contains("nikkor"))
            && (model.contains("10.5") || model.contains("10,5"))
    }

    private static func replacingParameter(
        _ name: String,
        value: Double,
        in tokens: [String]
    ) -> [String] {
        var replaced = false
        return tokens.map { token in
            guard !replaced, token.hasPrefix(name) else { return token }
            replaced = true
            return "\(name)\(String(value))"
        }
    }

    static func makeRigOptimizationProject(
        from sourceProject: URL,
        to destinationProject: URL,
        imageCount: Int,
        fillOnlyIndices: Set<Int>
    ) throws {
        let source = try String(contentsOf: sourceProject, encoding: .utf8)
        var lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
            .map(String.init)
            .filter { line in
                !line.hasPrefix("v ")
                    && !(line.hasPrefix("c ")
                        && controlPoint(line, usesAnyImageIn: fillOnlyIndices))
            }
        lines.append(contentsOf: [
            "v v0",
            "v b0",
            "v d0",
            "v e0"
        ])
        let alignmentIndices = (0..<imageCount).filter {
            !fillOnlyIndices.contains($0)
        }
        for index in alignmentIndices.dropFirst() {
            lines.append("v y\(index) p\(index) r\(index)")
        }
        try lines.joined(separator: "\n").write(
            to: destinationProject,
            atomically: true,
            encoding: .utf8
        )
    }

    static func makeFillImageOptimizationProject(
        rigProject: URL,
        controlPointProject: URL,
        output: URL,
        fillOnlyIndices: Set<Int>
    ) throws {
        let rig = try String(contentsOf: rigProject, encoding: .utf8)
        let controlPoints = try String(
            contentsOf: controlPointProject,
            encoding: .utf8
        )
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                line.hasPrefix("c ")
                    && controlPoint(line, usesAnyImageIn: fillOnlyIndices)
            }
        var lines = rig.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
            .map(String.init)
            .filter { !$0.hasPrefix("v ") }
        lines.append(contentsOf: controlPoints)
        for index in fillOnlyIndices.sorted() {
            lines.append(
                "v y\(index) p\(index) r\(index) "
                    + "TrX\(index) TrY\(index) TrZ\(index)"
            )
        }
        try lines.joined(separator: "\n").write(
            to: output,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func controlPoint(
        _ line: String,
        usesAnyImageIn indices: Set<Int>
    ) -> Bool {
        line.split(separator: " ").contains { token in
            indices.contains { index in
                token == "n\(index)" || token == "N\(index)"
            }
        }
    }

    private static func toolsDirectory() -> URL {
        let bundled = Bundle.main.bundleURL
            .appending(path: "Contents/Resources/Hugin/MacOS", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: bundled.path()) {
            return bundled
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Vendor/Hugin/MacOS", directoryHint: .isDirectory)
    }

    private static func run(
        _ executable: String,
        arguments: [String],
        toolsDirectory: URL,
        workDirectory: URL
    ) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = toolsDirectory.appending(path: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["OMP_NUM_THREADS"] = "1"
        process.environment = environment
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .suffix(8)
                .joined(separator: "\n")
                ?? "Okänt fel"
            throw PanoramaEngineError.stitchingFailed(
                "\(executable) misslyckades:\n\(detail)"
            )
        }
    }
}
