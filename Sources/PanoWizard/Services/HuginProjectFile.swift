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

    static func configuringRingOptimization(
        in project: URL,
        imageCount: Int
    ) throws {
        var lines = try contents(of: project).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        if let firstImageIndex = lines.firstIndex(where: {
            $0.hasPrefix("i ")
        }) {
            var calibratedLens = lines[firstImageIndex]
            calibratedLens = replacing("a", with: -0.17, in: calibratedLens)
            calibratedLens = replacing("b", with: 0.32, in: calibratedLens)
            calibratedLens = replacing("c", with: -0.18, in: calibratedLens)
            // PTGui stores the optimized short-/long-side center shifts as
            // image fractions. For 2600×3888 these become -26.093 and
            // -46.95 pixels in Hugin's d/e coordinate system.
            calibratedLens = replacing("d", with: -26.093, in: calibratedLens)
            calibratedLens = replacing("e", with: -46.95, in: calibratedLens)
            lines[firstImageIndex] = calibratedLens
        }
        lines.removeAll { $0.hasPrefix("v ") || $0 == "v" }
        let insertionIndex = lines.firstIndex(of: "# control points")
            ?? lines.endIndex
        var variables = [
            "v v0"
        ]
        for imageIndex in 0..<imageCount {
            variables += [
                "v y\(imageIndex)",
                "v p\(imageIndex)",
                "v r\(imageIndex)"
            ]
        }
        variables += ["v", ""]
        lines.insert(contentsOf: variables, at: insertionIndex)
        try write(lines, to: project)
    }

    static func configuringNikon105RingOptimization(
        in project: URL,
        imageCount: Int,
        horizontalFieldOfView: Double
    ) throws {
        var imageIndex = 0
        var lines = try contents(of: project).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { substring -> String in
            var line = String(substring)
            guard line.hasPrefix("i ") else { return line }
            // PTGui's Nikkor profile uses fisheye factor -0.599227.
            // Hugin cannot represent an arbitrary fisheye factor; its
            // equisolid projection (-0.5) plus the calibrated a/b/c residual
            // is the closest equivalent and fits Panorama G's PTGui control
            // points far better than equidistant full-frame fisheye.
            line = replacingProjection(with: 21, in: line)
            if imageIndex == 0 {
                // Calibrated from the six-image tripod reference Panorama G
                // in PTGui 13.9. Full-frame fisheye coefficients use the
                // same short-side normalization as Hugin.
                line = replacing("v", with: horizontalFieldOfView, in: line)
                // PTGui's residual coefficients and long-/short-side shift
                // are defined around its exact -0.599227 base projection.
                // These are their fitted Hugin f21 equivalents, measured
                // against all 150 PTGui control points in Panorama G.
                line = replacing("a", with: -0.0252155339841942, in: line)
                line = replacing("b", with: 0.0605540979849503, in: line)
                line = replacing("c", with: -0.055438892095899, in: line)
                line = replacing("d", with: 4.19324585683399, in: line)
                line = replacing("e", with: -1.00751194420142, in: line)
            }
            imageIndex += 1
            return line
        }
        lines.removeAll { $0.hasPrefix("v ") || $0 == "v" }
        let insertionIndex = lines.firstIndex(of: "# control points")
            ?? lines.endIndex
        var variables: [String] = []
        for index in 0..<imageCount {
            variables += ["v y\(index)", "v p\(index)", "v r\(index)"]
        }
        variables += ["v", ""]
        lines.insert(contentsOf: variables, at: insertionIndex)
        try write(lines, to: project)
    }

    static func configuringNikon105PoseOptimization(
        from source: URL,
        to destination: URL,
        nominalYaws: [Double],
        horizontalFieldOfView: Double
    ) throws {
        var imageIndex = 0
        var lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { substring -> String in
            var line = String(substring)
            guard line.hasPrefix("i ") else { return line }
            line = replacingProjection(with: 21, in: line)
            if imageIndex == 0 {
                line = replacing("v", with: horizontalFieldOfView, in: line)
            }
            line = replacing("y", with: nominalYaws[imageIndex], in: line)
            line = replacing("p", with: 0, in: line)
            line = replacing("r", with: 0, in: line)
            imageIndex += 1
            return line
        }
        lines.removeAll { $0.hasPrefix("v ") || $0 == "v" }
        let insertionIndex = lines.firstIndex(of: "# control points")
            ?? lines.endIndex
        var variables: [String] = []
        for index in nominalYaws.indices {
            variables += ["v y\(index)", "v p\(index)", "v r\(index)"]
        }
        variables += ["v", ""]
        lines.insert(contentsOf: variables, at: insertionIndex)
        try write(lines, to: destination)
    }

    static func configuringNikon105LensRefinement(
        from source: URL,
        to destination: URL
    ) throws {
        var lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        lines.removeAll { $0.hasPrefix("v ") || $0 == "v" }
        let imageCount = lines.count { $0.hasPrefix("i ") }
        let insertionIndex = lines.firstIndex(of: "# control points")
            ?? lines.endIndex
        // Keep the calibrated distortion and optical center fixed. A small
        // field-of-view refinement absorbs body/sample variation without
        // letting lens and pose collapse together.
        var variables = ["v v0"]
        for index in 0..<imageCount {
            variables += ["v y\(index)", "v p\(index)", "v r\(index)"]
        }
        variables += ["v", ""]
        lines.insert(contentsOf: variables, at: insertionIndex)
        try write(lines, to: destination)
    }

    static func configuringSigmaPoseOptimization(
        from source: URL,
        to destination: URL,
        nominalYaws: [Double],
        horizontalFieldOfView: Double
    ) throws {
        var imageIndex = 0
        var lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { substring -> String in
            var line = String(substring)
            guard line.hasPrefix("i ") else { return line }
            line = replacingProjection(with: 21, in: line)
            if imageIndex == 0 {
                line = replacing("v", with: horizontalFieldOfView, in: line)
                // PTGui normalizes a/b/c against the circular crop radius,
                // while Hugin normalizes against half the short image side.
                // These are the PTGui Sigma 8 mm / Nikon DX coefficients
                // converted to Hugin's coordinate system.
                line = replacing("a", with: -0.06164565246503961, in: line)
                line = replacing("b", with: 0.16155732903077044, in: line)
                line = replacing("c", with: -0.12544199818788626, in: line)
            }
            let yaw = nominalYaws[imageIndex]
            line = replacing("y", with: yaw, in: line)
            line = replacing("p", with: 0, in: line)
            line = replacing("r", with: 0, in: line)
            imageIndex += 1
            return line
        }
        lines.removeAll { $0.hasPrefix("v ") || $0 == "v" }
        let insertionIndex = lines.firstIndex(of: "# control points")
            ?? lines.endIndex
        var variables: [String] = []
        for index in nominalYaws.indices {
            variables += ["v y\(index)", "v p\(index)", "v r\(index)"]
        }
        variables += ["v", ""]
        lines.insert(contentsOf: variables, at: insertionIndex)
        try write(lines, to: destination)
    }

    static func configuringSigmaLensRefinement(
        from source: URL,
        to destination: URL
    ) throws {
        var lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        lines.removeAll { $0.hasPrefix("v ") || $0 == "v" }
        let imageCount = lines.count { $0.hasPrefix("i ") }
        let insertionIndex = lines.firstIndex(of: "# control points")
            ?? lines.endIndex
        // PTGui's "heavy + shift" Sigma solve refines the optical centre as
        // well as radial distortion.  Leaving d/e fixed forces near-nadir
        // control points to bend the camera poses instead, producing a
        // visible discontinuity in regular ground patterns.
        var variables = [
            "v v0", "v a0", "v b0", "v c0", "v d0", "v e0"
        ]
        for index in 0..<imageCount {
            variables += ["v y\(index)", "v p\(index)", "v r\(index)"]
        }
        variables += ["v", ""]
        lines.insert(contentsOf: variables, at: insertionIndex)
        try write(lines, to: destination)
    }

    static func configuringPoseRefinement(
        from source: URL,
        to destination: URL
    ) throws {
        var lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        lines.removeAll { $0.hasPrefix("v ") || $0 == "v" }
        let imageCount = lines.count { $0.hasPrefix("i ") }
        let insertionIndex = lines.firstIndex(of: "# control points")
            ?? lines.endIndex
        var variables: [String] = []
        for index in 0..<imageCount {
            variables += ["v y\(index)", "v p\(index)", "v r\(index)"]
        }
        variables += ["v", ""]
        lines.insert(contentsOf: variables, at: insertionIndex)
        try write(lines, to: destination)
    }

    static func addingZenith(
        image: SourceImage,
        renderedImageURL: URL? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
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
        let calibratedLine = lines[imageIndices[0]]
        zenithLine = replacing("y", with: orientation.yaw, in: zenithLine)
        zenithLine = replacing("p", with: orientation.pitch, in: zenithLine)
        zenithLine = replacing("r", with: orientation.roll, in: zenithLine)
        if let pixelWidth {
            zenithLine = replacingInteger("w", with: pixelWidth, in: zenithLine)
        }
        if let pixelHeight {
            zenithLine = replacingInteger("h", with: pixelHeight, in: zenithLine)
        }
        if let pixelWidth,
           let calibratedWidth = integer("w", in: calibratedLine),
           pixelWidth != calibratedWidth,
           let calibratedFieldOfView = number("v", in: calibratedLine) {
            // The calibrated ring images are EXIF-oriented portrait images.
            // A hand-held pole image can instead be landscape. Hugin links
            // `v=0` by image width, which would apply the portrait HFOV to a
            // 50% wider image and make the repair vastly too large. Preserve
            // the calibrated equisolid focal length in pixels and derive the
            // corresponding landscape HFOV.
            let focalPixels = Double(calibratedWidth) / (
                4 * sin(calibratedFieldOfView * .pi / 720)
            )
            let ratio = min(1, Double(pixelWidth) / (4 * focalPixels))
            let repairFieldOfView = 720 / .pi * asin(ratio)
            zenithLine = replacingResolved(
                "v",
                with: repairFieldOfView,
                in: zenithLine
            )
            for parameter in ["a", "b", "c"] {
                if let value = number(parameter, in: calibratedLine) {
                    zenithLine = replacingResolved(
                        parameter,
                        with: value,
                        in: zenithLine
                    )
                }
            }
            // Rotating the sensor axes from portrait to landscape rotates the
            // calibrated optical-centre offset clockwise as well.
            if let d = number("d", in: calibratedLine),
               let e = number("e", in: calibratedLine) {
                zenithLine = replacingResolved("d", with: -e, in: zenithLine)
                zenithLine = replacingResolved("e", with: d, in: zenithLine)
            }
        }
        zenithLine = replacingFilename(
            (renderedImageURL ?? image.url).path(percentEncoded: false),
            in: zenithLine
        )
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
            line = replacingFilename(paths[imageIndex].path(percentEncoded: false), in: line)
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

    static func centeringPanoramaSeamBetweenRingImages(
        from source: URL,
        to destination: URL,
        ringImageCount: Int
    ) throws {
        guard ringImageCount > 1 else {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        let orientations = try orientations(in: source)
        guard let firstYaw = orientations.first else {
            throw PanoramaEngineError.stitchingFailed(
                "Panoramats kamerariktningar saknas."
            )
        }
        // Put the equirectangular boundary halfway between the first and last
        // ring cameras. Keeping it away from a camera centre prevents a
        // single fisheye layer from being split across both canvas edges,
        // which can make Enblend's seam optimizer leave a black wedge.
        let desiredFirstYaw = -180 + 180 / Double(ringImageCount)
        let yawOffset = desiredFirstYaw - firstYaw.yaw
        let lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { substring -> String in
            var line = String(substring)
            guard line.hasPrefix("i "), let yaw = number("y", in: line) else {
                return line
            }
            var rotatedYaw = (yaw + yawOffset).truncatingRemainder(
                dividingBy: 360
            )
            if rotatedYaw < -180 { rotatedYaw += 360 }
            if rotatedYaw >= 180 { rotatedYaw -= 360 }
            line = replacing("y", with: rotatedYaw, in: line)
            return line
        }
        try write(lines, to: destination)
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

    static func controlPoints(in project: URL) throws -> [DiagnosticControlPoint] {
        try contents(of: project).split(separator: "\n").compactMap {
            let line = String($0)
            guard line.hasPrefix("c "),
                  let firstImage = integer("n", in: line),
                  let secondImage = integer("N", in: line),
                  let firstX = number("x", in: line),
                  let firstY = number("y", in: line),
                  let secondX = number("X", in: line),
                  let secondY = number("Y", in: line) else {
                return nil
            }
            return DiagnosticControlPoint(
                firstImage: firstImage,
                secondImage: secondImage,
                firstX: firstX,
                firstY: firstY,
                secondX: secondX,
                secondY: secondY
            )
        }
    }

    static func filteringControlPoints(
        from source: URL,
        to destination: URL,
        keeping predicate: (DiagnosticControlPoint) -> Bool
    ) throws {
        let lines = try contents(of: source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).compactMap { substring -> String? in
            let line = String(substring)
            guard line.hasPrefix("c ") else { return line }
            guard let point = controlPoint(in: line) else { return line }
            return predicate(point) ? line : nil
        }
        try write(lines, to: destination)
    }

    static func filteringImplausibleRingPairs(
        from source: URL,
        to destination: URL,
        nominalYaws: [Double]
    ) throws {
        let distinctYawCount = Set(nominalYaws).count
        let nominalStep = 360.0 / Double(max(distinctYawCount, 1))
        try filteringControlPoints(from: source, to: destination) { point in
            guard point.firstImage < nominalYaws.count,
                  point.secondImage < nominalYaws.count else {
                return false
            }
            let difference = abs(
                nominalYaws[point.firstImage]
                    - nominalYaws[point.secondImage]
            ).truncatingRemainder(dividingBy: 360)
            let circularDifference = min(difference, 360 - difference)
            return circularDifference <= nominalStep * 1.5
        }
    }

    static func filteringToRingBackbone(
        from source: URL,
        to destination: URL,
        nominalYaws: [Double]
    ) throws {
        let points = try controlPoints(in: source)
        let groups = Dictionary(grouping: nominalYaws.indices) {
            nominalYaws[$0]
        }
        .sorted { $0.key < $1.key }
        .map(\.value)
        guard groups.count >= 2 else {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }

        let counts = Dictionary(grouping: points, by: \.pair).mapValues(\.count)
        var bestRepresentatives = groups.map { $0[0] }
        var bestScore = Int.min
        var candidate: [Int] = []

        func search(_ groupIndex: Int) {
            if groupIndex == groups.count {
                var score = 0
                for index in candidate.indices {
                    let first = candidate[index]
                    let second = candidate[(index + 1) % candidate.count]
                    let pair = ControlPointPair.ID(
                        firstImage: min(first, second),
                        secondImage: max(first, second)
                    )
                    let count = counts[pair, default: 0]
                    score += count == 0 ? -1_000 : count
                }
                if score > bestScore {
                    bestScore = score
                    bestRepresentatives = candidate
                }
                return
            }
            for imageIndex in groups[groupIndex] {
                candidate.append(imageIndex)
                search(groupIndex + 1)
                candidate.removeLast()
            }
        }
        search(0)
        let representatives = Set(bestRepresentatives)

        try filteringControlPoints(from: source, to: destination) { point in
            guard point.firstImage < nominalYaws.count,
                  point.secondImage < nominalYaws.count else {
                return false
            }
            let sameDirection =
                nominalYaws[point.firstImage] == nominalYaws[point.secondImage]
            return sameDirection
                || representatives.contains(point.firstImage)
                    && representatives.contains(point.secondImage)
        }
    }

    static func inferredRingYaws(
        in project: URL,
        imageCount: Int
    ) throws -> [Double] {
        let grouped = Dictionary(grouping: try controlPoints(in: project)) {
            $0.pair
        }
        let duplicatePairs: Set<ControlPointPair.ID> = Set(
            grouped.compactMap { pair, points -> ControlPointPair.ID? in
            // Duplicate exposures often have only a handful of deliberately
            // edited points. Six well-distributed points are enough to detect
            // that they share a camera direction; requiring twelve caused
            // Panorama F's four directions to be seeded as nine directions.
            guard points.count >= 6 else { return nil }
            let displacements = points.map {
                hypot($0.firstX - $0.secondX, $0.firstY - $0.secondY)
            }.sorted()
            let median = displacements[displacements.count / 2]
                return median < 250 ? pair : nil
            }
        )

        // Duplicate similarity is not transitive for neighboring fisheye
        // views. In particular, A≈B and B≈C does not imply A≈C. Requiring a
        // candidate to match every member prevents two neighboring camera
        // directions from being merged through one ambiguous image.
        var directionGroups: [[Int]] = []
        for imageIndex in 0..<imageCount {
            if let groupIndex = directionGroups.firstIndex(where: { group in
                group.allSatisfy { member in
                    duplicatePairs.contains(
                        ControlPointPair.ID(
                            firstImage: min(imageIndex, member),
                            secondImage: max(imageIndex, member)
                        )
                    )
                }
            }) {
                directionGroups[groupIndex].append(imageIndex)
            } else {
                directionGroups.append([imageIndex])
            }
        }

        let step = 360.0 / Double(directionGroups.count)
        var yaws = Array(repeating: 0.0, count: imageCount)
        for (groupIndex, group) in directionGroups.enumerated() {
            for imageIndex in group {
                yaws[imageIndex] = Double(groupIndex) * step
            }
        }
        return yaws
    }

    private static func controlPointLine(
        _ controlPoint: PanoramaControlPoint
    ) -> String {
        "c n\(controlPoint.firstImage) N\(controlPoint.secondImage) "
            + "x\(controlPoint.firstX) y\(controlPoint.firstY) "
            + "X\(controlPoint.secondX) Y\(controlPoint.secondY) t0"
    }


    private static func controlPoint(
        in line: String
    ) -> DiagnosticControlPoint? {
        guard let firstImage = integer("n", in: line),
              let secondImage = integer("N", in: line),
              let firstX = number("x", in: line),
              let firstY = number("y", in: line),
              let secondX = number("X", in: line),
              let secondY = number("Y", in: line) else {
            return nil
        }
        return DiagnosticControlPoint(
            firstImage: firstImage,
            secondImage: secondImage,
            firstX: firstX,
            firstY: firstY,
            secondX: secondX,
            secondY: secondY
        )
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

    private static func replacingInteger(
        _ parameter: String,
        with value: Int,
        in line: String
    ) -> String {
        let pattern = #"((?:^| )\#(parameter))[0-9]+(?= |$)"#
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

    private static func replacingResolved(
        _ parameter: String,
        with value: Double,
        in line: String
    ) -> String {
        let pattern = #"((?:^| )\#(parameter))(?:=[0-9]+|-?[0-9]+(?:\.[0-9]+)?)(?= |$)"#
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

    private static func replacingProjection(
        with projection: Int,
        in line: String
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"((?:^| )f)[0-9]+(?= |$)"#
        ) else {
            return line
        }
        return expression.stringByReplacingMatches(
            in: line,
            range: NSRange(line.startIndex..., in: line),
            withTemplate: "$1\(projection)"
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

    private static func integer(_ name: String, in line: String) -> Int? {
        number(name, in: line).map { Int($0) }
    }
}
