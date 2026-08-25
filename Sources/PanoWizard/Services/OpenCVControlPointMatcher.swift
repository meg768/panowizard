import Foundation
import OpenCVBridge

struct PanoramaControlPoint: Sendable {
    let firstImage: Int
    let secondImage: Int
    let firstX: Double
    let firstY: Double
    let secondX: Double
    let secondY: Double
}

struct PanoramaOrientation: Equatable, Sendable {
    let yaw: Double
    let pitch: Double
    let roll: Double
}

struct PositioningGeometryEvidence: Equatable, Sendable {
    let orientation: PanoramaOrientation
    let pointCount: Int
    let connectedImageCount: Int
    let medianResidualDegrees: Double
    let p90ResidualDegrees: Double
    let contaminatedRigMedianResidualDegrees: Double
    let contaminatedRigP90ResidualDegrees: Double
    let rigMedianResidualDegrees: Double
    let rigP90ResidualDegrees: Double
}

struct ControlPointPairGenerationDiagnostic: Equatable, Sendable {
    let firstImage: Int
    let secondImage: Int
    let firstFeatureCount: Int
    let secondFeatureCount: Int
    let ratioMatchCount: Int
    let mutualMatchCount: Int
    let geometricMatchCount: Int
    let selectedControlPointCount: Int
    let meanReprojectionError: Double
    let spatialCoverage: Double
}

enum OpenCVControlPointMatcher {
    nonisolated(unsafe) private(set) static var lastPairDiagnostics:
        [ControlPointPairGenerationDiagnostic] = []
    static func pair(
        images: [SourceImage],
        pair: ControlPointPair.ID,
        horizontalFieldOfView: Double,
        lensProfile: StitchingConfiguration.LensProfile? = nil
    ) throws -> [PanoramaControlPoint] {
        guard images.indices.contains(pair.firstImage),
              images.indices.contains(pair.secondImage) else {
            throw PanoramaEngineError.stitchingFailed(
                "Det valda bildparet finns inte."
            )
        }
        let firstURL = images[pair.firstImage].url
        let secondURL = images[pair.secondImage].url

        var rawPoints: UnsafeMutablePointer<PWControlPoint>?
        var pointCount: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let bridgeLensModel = bridgeLensModel(
            images: [images[pair.firstImage], images[pair.secondImage]],
            horizontalFieldOfView: horizontalFieldOfView,
            lensProfile: lensProfile
        )
        let succeeded = firstURL.path.withCString {
            firstPath in
            secondURL.path.withCString { secondPath in
                PWGeneratePairControlPoints(
                    firstPath,
                    secondPath,
                    Int32(pair.firstImage),
                    Int32(pair.secondImage),
                    Int32(images.count),
                    horizontalFieldOfView,
                    bridgeLensModel,
                    &rawPoints,
                    &pointCount,
                    &errorMessage
                )
            }
        }
        return try result(
            succeeded: succeeded,
            rawPoints: rawPoints,
            pointCount: pointCount,
            errorMessage: errorMessage
        )
    }

    static func ring(
        images: [SourceImage],
        horizontalFieldOfView: Double,
        lensProfile: StitchingConfiguration.LensProfile? = nil,
        nominalYaws: [Double]? = nil
    ) throws -> [PanoramaControlPoint] {
        precondition(nominalYaws == nil || nominalYaws?.count == images.count)
        return try withImagePaths(images) { paths in
            let bridgeLensModel = bridgeLensModel(
                images: images,
                horizontalFieldOfView: horizontalFieldOfView,
                lensProfile: lensProfile
            )
            var rawPoints: UnsafeMutablePointer<PWControlPoint>?
            var pointCount: Int32 = 0
            var errorMessage: UnsafeMutablePointer<CChar>?
            // Every image passed here has the role "Ingår i positionering".
            // Its old direction value belongs only to the repair UI and must
            // not change CP generation or sparse-overlap recovery.
            let positioningImageFlags = Array(
                repeating: Int32(1),
                count: images.count
            )
            let succeeded = positioningImageFlags.withUnsafeBufferPointer {
                flags in
                nominalYaws?.withUnsafeBufferPointer { yaws in
                    PWGenerateRingControlPoints(
                        paths.baseAddress,
                        yaws.baseAddress,
                        flags.baseAddress,
                        Int32(paths.count),
                        horizontalFieldOfView,
                        bridgeLensModel,
                        &rawPoints,
                        &pointCount,
                        &errorMessage
                    )
                } ?? PWGenerateRingControlPoints(
                    paths.baseAddress,
                    nil,
                    flags.baseAddress,
                    Int32(paths.count),
                    horizontalFieldOfView,
                    bridgeLensModel,
                    &rawPoints,
                    &pointCount,
                    &errorMessage
                )
            }
            // The bridge also records diagnostics when it cannot connect the
            // image graph. Preserve those details before propagating the
            // failure so callers can explain which overlap was missing.
            lastPairDiagnostics = copyLastPairDiagnostics()
            let points = try result(
                succeeded: succeeded,
                rawPoints: rawPoints,
                pointCount: pointCount,
                errorMessage: errorMessage
            )
            let weakPairs = nominalYaws == nil
                && horizontalFieldOfView >= 110
                ? weakWideFisheyePairs(in: lastPairDiagnostics) : []
            if nominalYaws == nil,
               bridgeLensModel != 0,
               needsSparseCycleProtection(in: lastPairDiagnostics) {
                for diagnostic in lastPairDiagnostics {
                    print(
                        "[PanoWizard] CP failure pair "
                            + "\(diagnostic.firstImage)-"
                            + "\(diagnostic.secondImage): selected="
                            + "\(diagnostic.selectedControlPointCount) coverage="
                            + String(format: "%.3f", diagnostic.spatialCoverage)
                    )
                }
                // Circular-fisheye rings can have a very narrow textured
                // closing overlap. Keep those points until the global bundle
                // adjustment can judge their actual residuals; the engine
                // still rejects sparse transitions that do not become
                // geometrically consistent.
                return points
            }
            if !weakPairs.isEmpty {
                print(
                    "[PanoWizard] Deferring weak CP pairs to bundle adjustment: "
                        + weakPairs.map { "\($0.0)-\($0.1)" }
                            .joined(separator: ", ")
                )
            }
            // A narrow overlap can carry disproportionately valuable polar
            // constraints. Keep every geometrically established pair until
            // cpclean and the residual-based global pass can judge it in the
            // context of the complete rig.
            return points
        }
    }

    static func initialOrientations(
        images: [SourceImage],
        controlPoints: [PanoramaControlPoint],
        horizontalFieldOfView: Double,
        lensProfile: StitchingConfiguration.LensProfile
    ) throws -> [PanoramaOrientation] {
        guard images.count >= 2, !controlPoints.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "Underlaget för sfäriska startposer är ofullständigt."
            )
        }
        var rawPoints = controlPoints.map {
            PWControlPoint(
                firstImage: Int32($0.firstImage),
                secondImage: Int32($0.secondImage),
                firstX: $0.firstX,
                firstY: $0.firstY,
                secondX: $0.secondX,
                secondY: $0.secondY
            )
        }
        let widths = images.map { Int32($0.pixelWidth) }
        let heights = images.map { Int32($0.pixelHeight) }
        var rawOrientations = Array(
            repeating: PWOrientation(yaw: 0, pitch: 0, roll: 0),
            count: images.count
        )
        var errorMessage: UnsafeMutablePointer<CChar>?
        let lensModel = bridgeLensModel(
            images: images,
            horizontalFieldOfView: horizontalFieldOfView,
            lensProfile: lensProfile
        )
        let succeeded = rawPoints.withUnsafeMutableBufferPointer { points in
            widths.withUnsafeBufferPointer { widths in
                heights.withUnsafeBufferPointer { heights in
                    rawOrientations.withUnsafeMutableBufferPointer {
                        orientations in
                        PWEstimateControlPointOrientations(
                            points.baseAddress,
                            Int32(points.count),
                            widths.baseAddress,
                            heights.baseAddress,
                            Int32(images.count),
                            horizontalFieldOfView,
                            lensModel,
                            orientations.baseAddress,
                            &errorMessage
                        )
                    }
                }
            }
        }
        defer { PWFreeString(errorMessage) }
        guard succeeded != 0 else {
            let message = errorMessage.map { String(cString: $0) }
                ?? "De sfäriska startposerna kunde inte beräknas."
            throw PanoramaEngineError.stitchingFailed(message)
        }
        return rawOrientations.map {
            PanoramaOrientation(yaw: $0.yaw, pitch: $0.pitch, roll: $0.roll)
        }
    }

    static func positioningGeometryEvidence(
        images: [SourceImage],
        controlPoints: [PanoramaControlPoint],
        horizontalFieldOfView: Double,
        lensProfile: StitchingConfiguration.LensProfile
    ) throws -> [PositioningGeometryEvidence] {
        guard images.count >= 2, !controlPoints.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "Underlaget för geometrisk positioneringsevidens är "
                    + "ofullständigt."
            )
        }
        var rawPoints = controlPoints.map {
            PWControlPoint(
                firstImage: Int32($0.firstImage),
                secondImage: Int32($0.secondImage),
                firstX: $0.firstX,
                firstY: $0.firstY,
                secondX: $0.secondX,
                secondY: $0.secondY
            )
        }
        let widths = images.map { Int32($0.pixelWidth) }
        let heights = images.map { Int32($0.pixelHeight) }
        var rawEvidence = Array(
            repeating: PWPositioningEvidence(
                yaw: 0,
                pitch: 0,
                roll: 0,
                pointCount: 0,
                connectedImageCount: 0,
                medianResidualDegrees: 0,
                p90ResidualDegrees: 0,
                contaminatedRigMedianResidualDegrees: 0,
                contaminatedRigP90ResidualDegrees: 0,
                rigMedianResidualDegrees: 0,
                rigP90ResidualDegrees: 0
            ),
            count: images.count
        )
        var errorMessage: UnsafeMutablePointer<CChar>?
        let lensModel = bridgeLensModel(
            images: images,
            horizontalFieldOfView: horizontalFieldOfView,
            lensProfile: lensProfile
        )
        let succeeded = rawPoints.withUnsafeMutableBufferPointer { points in
            widths.withUnsafeBufferPointer { widths in
                heights.withUnsafeBufferPointer { heights in
                    rawEvidence.withUnsafeMutableBufferPointer { evidence in
                        PWEstimatePositioningEvidence(
                            points.baseAddress,
                            Int32(points.count),
                            widths.baseAddress,
                            heights.baseAddress,
                            Int32(images.count),
                            horizontalFieldOfView,
                            lensModel,
                            evidence.baseAddress,
                            &errorMessage
                        )
                    }
                }
            }
        }
        defer { PWFreeString(errorMessage) }
        guard succeeded != 0 else {
            let message = errorMessage.map { String(cString: $0) }
                ?? "Geometrisk positioneringsevidens kunde inte beräknas."
            throw PanoramaEngineError.stitchingFailed(message)
        }
        return rawEvidence.map {
            PositioningGeometryEvidence(
                orientation: PanoramaOrientation(
                    yaw: $0.yaw,
                    pitch: $0.pitch,
                    roll: $0.roll
                ),
                pointCount: Int($0.pointCount),
                connectedImageCount: Int($0.connectedImageCount),
                medianResidualDegrees: $0.medianResidualDegrees,
                p90ResidualDegrees: $0.p90ResidualDegrees,
                contaminatedRigMedianResidualDegrees:
                    $0.contaminatedRigMedianResidualDegrees,
                contaminatedRigP90ResidualDegrees:
                    $0.contaminatedRigP90ResidualDegrees,
                rigMedianResidualDegrees: $0.rigMedianResidualDegrees,
                rigP90ResidualDegrees: $0.rigP90ResidualDegrees
            )
        }
    }

    private static func bridgeLensModel(
        images: [SourceImage],
        horizontalFieldOfView: Double,
        lensProfile: StitchingConfiguration.LensProfile?
    ) -> Int32 {
        switch lensProfile {
        case .nikon105DX:
            return 1
        case .sigma8DX:
            return 2
        case .automatic, .custom:
            return 0
        case nil:
            if horizontalFieldOfView >= 110 {
                return 2
            }
            return images.allSatisfy { $0.lens.kind == .fisheye } ? 1 : 0
        }
    }

    static func weakWideFisheyePairs(
        in diagnostics: [ControlPointPairGenerationDiagnostic]
    ) -> [(Int, Int)] {
        diagnostics.compactMap { diagnostic in
            // This is diagnostic only. Wide-fisheye links are no longer
            // removed before bundle adjustment because a narrow overlap can
            // contain the only useful constraints near a pole.
            guard diagnostic.selectedControlPointCount > 0,
                  diagnostic.selectedControlPointCount < 10
                    || diagnostic.spatialCoverage < 0.1 else {
                return nil
            }
            return (diagnostic.firstImage, diagnostic.secondImage)
        }
    }

    static func needsSparseCycleProtection(
        in diagnostics: [ControlPointPairGenerationDiagnostic]
    ) -> Bool {
        let candidateEdges = diagnostics.compactMap { diagnostic in
            diagnostic.selectedControlPointCount >= 6
                ? (diagnostic.firstImage, diagnostic.secondImage) : nil
        }
        let strongEdges = diagnostics.compactMap { diagnostic in
            diagnostic.selectedControlPointCount >= 10
                && diagnostic.spatialCoverage >= 0.1
                ? (diagnostic.firstImage, diagnostic.secondImage) : nil
        }
        return graphContainsCycle(candidateEdges)
            && !graphContainsCycle(strongEdges)
    }

    private static func graphContainsCycle(_ edges: [(Int, Int)]) -> Bool {
        var adjacency: [Int: [Int]] = [:]
        for (first, second) in edges {
            adjacency[first, default: []].append(second)
            adjacency[second, default: []].append(first)
        }
        var visited = Set<Int>()
        func visit(_ image: Int, parent: Int?) -> Bool {
            visited.insert(image)
            for neighbor in adjacency[image, default: []] {
                if neighbor == parent { continue }
                if visited.contains(neighbor) || visit(neighbor, parent: image) {
                    return true
                }
            }
            return false
        }
        for image in adjacency.keys where !visited.contains(image) {
            if visit(image, parent: nil) { return true }
        }
        return false
    }

    static func weakFourImageRingPairs(
        in diagnostics: [ControlPointPairGenerationDiagnostic]
    ) -> [(Int, Int)] {
        weakPositioningSequenceTransitions(
            in: diagnostics,
            positioningImageIndices: Array(0..<4)
        )
    }

    static func weakPositioningSequenceTransitions(
        in diagnostics: [ControlPointPairGenerationDiagnostic],
        positioningImageIndices: [Int]
    ) -> [(Int, Int)] {
        guard positioningImageIndices.count >= 2 else { return [] }
        let requiredPairIDs = Set(positioningImageIndices.indices.map {
            position in
            let first = positioningImageIndices[position]
            let second = positioningImageIndices[
                (position + 1) % positioningImageIndices.count
            ]
            return ControlPointPair.ID(
                firstImage: min(first, second),
                secondImage: max(first, second)
            )
        })
        let requiredPairs = requiredPairIDs.sorted().map {
            ($0.firstImage, $0.secondImage)
        }
        return requiredPairs.filter { first, second in
            guard let diagnostic = diagnostics.first(where: {
                $0.firstImage == first && $0.secondImage == second
            }) else { return true }
            return diagnostic.selectedControlPointCount < 10
                || diagnostic.spatialCoverage < 0.1
        }
    }

    static func zenith(
        ringImages: [SourceImage],
        ringOrientations: [PanoramaOrientation],
        zenithImage: SourceImage,
        horizontalFieldOfView: Double
    ) throws -> (
        orientation: PanoramaOrientation,
        controlPoints: [PanoramaControlPoint]
    ) {
        guard ringImages.count == ringOrientations.count else {
            throw PanoramaEngineError.stitchingFailed(
                "Ringens bildgeometri är ofullständig."
            )
        }

        return try withImagePaths(ringImages) { paths in
            var rawOrientations = ringOrientations.map {
                PWOrientation(yaw: $0.yaw, pitch: $0.pitch, roll: $0.roll)
            }
            var zenithOrientation = PWOrientation(yaw: 0, pitch: 90, roll: 0)
            var rawPoints: UnsafeMutablePointer<PWControlPoint>?
            var pointCount: Int32 = 0
            var errorMessage: UnsafeMutablePointer<CChar>?

            let succeeded = rawOrientations.withUnsafeMutableBufferPointer {
                orientations in
                zenithImage.url.path.withCString { zenithPath in
                    PWGenerateZenithControlPoints(
                        paths.baseAddress,
                        orientations.baseAddress,
                        Int32(paths.count),
                        zenithPath,
                        horizontalFieldOfView,
                        &zenithOrientation,
                        &rawPoints,
                        &pointCount,
                        &errorMessage
                    )
                }
            }
            let points = try result(
                succeeded: succeeded,
                rawPoints: rawPoints,
                pointCount: pointCount,
                errorMessage: errorMessage
            )
            return (
                PanoramaOrientation(
                    yaw: zenithOrientation.yaw,
                    pitch: zenithOrientation.pitch,
                    roll: zenithOrientation.roll
                ),
                points
            )
        }
    }

    private static func withImagePaths<Result>(
        _ images: [SourceImage],
        body: (
            UnsafeBufferPointer<UnsafePointer<CChar>?>
        ) throws -> Result
    ) throws -> Result {
        let duplicatedPaths: [UnsafeMutablePointer<CChar>] = try images.map {
            guard let path = strdup($0.url.path) else {
                throw PanoramaEngineError.stitchingFailed(
                    "Bildsökvägen kunde inte förberedas."
                )
            }
            return path
        }
        defer {
            duplicatedPaths.forEach { free($0) }
        }
        let paths: [UnsafePointer<CChar>?] = duplicatedPaths.map {
            UnsafePointer($0)
        }
        return try paths.withUnsafeBufferPointer(body)
    }

    private static func result(
        succeeded: Int32,
        rawPoints: UnsafeMutablePointer<PWControlPoint>?,
        pointCount: Int32,
        errorMessage: UnsafeMutablePointer<CChar>?
    ) throws -> [PanoramaControlPoint] {
        defer {
            PWFreeControlPoints(rawPoints)
            PWFreeString(errorMessage)
        }
        guard succeeded != 0 else {
            let message = errorMessage.map { String(cString: $0) }
                ?? "OpenCV kunde inte skapa kontrollpunkter."
            throw PanoramaEngineError.stitchingFailed(message)
        }
        guard let rawPoints, pointCount > 0 else {
            return []
        }
        return UnsafeBufferPointer(
            start: rawPoints,
            count: Int(pointCount)
        ).map {
            PanoramaControlPoint(
                firstImage: Int($0.firstImage),
                secondImage: Int($0.secondImage),
                firstX: $0.firstX,
                firstY: $0.firstY,
                secondX: $0.secondX,
                secondY: $0.secondY
            )
        }
    }

    private static func copyLastPairDiagnostics()
        -> [ControlPointPairGenerationDiagnostic] {
        var rawDiagnostics: UnsafeMutablePointer<PWControlPointPairDiagnostic>?
        var count: Int32 = 0
        guard PWCopyLastControlPointPairDiagnostics(
            &rawDiagnostics,
            &count
        ) != 0 else { return [] }
        defer { PWFreeControlPointPairDiagnostics(rawDiagnostics) }
        guard let rawDiagnostics, count > 0 else { return [] }
        return UnsafeBufferPointer(
            start: rawDiagnostics,
            count: Int(count)
        ).map {
            ControlPointPairGenerationDiagnostic(
                firstImage: Int($0.firstImage),
                secondImage: Int($0.secondImage),
                firstFeatureCount: Int($0.firstFeatureCount),
                secondFeatureCount: Int($0.secondFeatureCount),
                ratioMatchCount: Int($0.ratioMatchCount),
                mutualMatchCount: Int($0.mutualMatchCount),
                geometricMatchCount: Int($0.geometricMatchCount),
                selectedControlPointCount: Int($0.selectedControlPointCount),
                meanReprojectionError: $0.meanReprojectionError,
                spatialCoverage: $0.spatialCoverage
            )
        }
    }
}
