import Foundation

enum HuginProjectFile {
    static func seedRing(
        from source: URL,
        to destination: URL,
        imageCount: Int
    ) throws {
        var imageIndex = 0
        let lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { substring -> String in
            var line = String(substring)
            guard line.hasPrefix("i ") else { return line }
            let yaw = Double(imageIndex) * 360 / Double(imageCount)
            line = replacing("y", with: yaw, in: line)
            line = replacing("p", with: 0, in: line)
            line = replacing("r", with: 0, in: line)
            imageIndex += 1
            return line
        }
        try write(lines, to: destination)
    }

    static func appending(
        controlPoints: [PanoramaControlPoint],
        from source: URL,
        to destination: URL
    ) throws {
        var project = try contents(of: source)
        if !project.hasSuffix("\n") {
            project += "\n"
        }
        project += controlPoints.map(controlPointLine).joined(separator: "\n")
        project += "\n"
        try project.write(to: destination, atomically: true, encoding: .utf8)
    }

    static func addingZenith(
        image: SourceImage,
        orientation: PanoramaOrientation,
        controlPoints: [PanoramaControlPoint],
        ringProject: URL,
        destination: URL
    ) throws {
        var lines = try contents(of: ringProject).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        let imageIndices = lines.indices.filter { lines[$0].hasPrefix("i ") }
        guard imageIndices.count >= 2, let lastImageIndex = imageIndices.last else {
            throw PanoramaEngineError.stitchingFailed(
                "Hugins ringprojekt är ofullständigt."
            )
        }

        var zenithLine = lines[imageIndices[1]]
        zenithLine = replacing("y", with: orientation.yaw, in: zenithLine)
        zenithLine = replacing("p", with: orientation.pitch, in: zenithLine)
        zenithLine = replacing("r", with: orientation.roll, in: zenithLine)
        zenithLine = replacingFilename(image.url.path(), in: zenithLine)
        lines.insert("#-hugin  cropFactor=1.5", at: lastImageIndex + 1)
        lines.insert(zenithLine, at: lastImageIndex + 2)

        lines.removeAll { $0.hasPrefix("v ") || $0 == "v" }
        let variableIndex = lines.firstIndex(of: "# control points")
            ?? lines.endIndex
        let zenithIndex = imageIndices.count
        lines.insert(
            contentsOf: [
                "v y\(zenithIndex)",
                "v p\(zenithIndex)",
                "v r\(zenithIndex)",
                "v",
                ""
            ],
            at: variableIndex
        )
        lines.append(contentsOf: controlPoints.map(controlPointLine))
        try write(lines, to: destination)
    }

    static func replacingImagePaths(
        in source: URL,
        with paths: [URL],
        destination: URL
    ) throws {
        var imageIndex = 0
        let lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { substring -> String in
            var line = String(substring)
            guard line.hasPrefix("i "), imageIndex < paths.count else {
                return line
            }
            line = replacingFilename(paths[imageIndex].path(), in: line)
            imageIndex += 1
            return line
        }
        try write(lines, to: destination)
    }

    static func imageLines(in project: URL) throws -> [String] {
        try contents(of: project).split(separator: "\n").compactMap {
            $0.hasPrefix("i ") ? String($0) : nil
        }
    }

    static func orientations(in project: URL) throws -> [PanoramaOrientation] {
        try imageLines(in: project).map { line in
            guard let yaw = number("y", in: line),
                  let pitch = number("p", in: line),
                  let roll = number("r", in: line) else {
                throw PanoramaEngineError.stitchingFailed(
                    "En kamerariktning saknas i Hugin-projektet."
                )
            }
            return PanoramaOrientation(yaw: yaw, pitch: pitch, roll: roll)
        }
    }

    static func horizontalFieldOfView(in project: URL) throws -> Double {
        guard let first = try imageLines(in: project).first,
              let fieldOfView = number("v", in: first) else {
            throw PanoramaEngineError.stitchingFailed(
                "Objektivets bildvinkel saknas i Hugin-projektet."
            )
        }
        return fieldOfView
    }

    private static func controlPointLine(
        _ controlPoint: PanoramaControlPoint
    ) -> String {
        "c n\(controlPoint.firstImage) N\(controlPoint.secondImage) "
            + "x\(controlPoint.firstX) y\(controlPoint.firstY) "
            + "X\(controlPoint.secondX) Y\(controlPoint.secondY) t0"
    }

    private static func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private static func write(_ lines: [String], to url: URL) throws {
        try lines.joined(separator: "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func replacing(
        _ parameter: String,
        with value: Double,
        in line: String
    ) -> String {
        let pattern = #"((?:^| )\#(parameter))-?[0-9]+(?:\.[0-9]+)?(?= |$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        return expression.stringByReplacingMatches(
            in: line,
            range: range,
            withTemplate: "$1\(value)"
        )
    }

    private static func replacingFilename(
        _ filename: String,
        in line: String
    ) -> String {
        let escaped = filename
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        guard let expression = try? NSRegularExpression(pattern: #" n"[^"]*""#)
        else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        return expression.stringByReplacingMatches(
            in: line,
            range: range,
            withTemplate: " n\"\(escaped)\""
        )
    }

    private static func number(_ name: String, in line: String) -> Double? {
        let pattern = "(?:^|\\s)\(name)(-?[0-9]+(?:\\.[0-9]+)?)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Double(line[valueRange])
    }
}
