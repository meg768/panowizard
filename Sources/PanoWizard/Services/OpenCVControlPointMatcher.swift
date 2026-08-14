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
        lensProfile: StitchingConfiguration.LensProfile? = nil,
        controlPointMasks: [UUID: Data] = [:]
    ) throws -> [PanoramaControlPoint] {
        guard images.indices.contains(pair.firstImage),
              images.indices.contains(pair.secondImage) else {
            throw PanoramaEngineError.stitchingFailed(
                "Det valda bildparet finns inte."
            )
        }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/PairMatching/\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        func matchingURL(for image: SourceImage, name: String) throws -> URL {
            guard let mask = controlPointMasks[image.id] else {
                return image.url
            }
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            let destination = temporaryDirectory.appending(path: "\(name).tif")
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: mask,
                destinationURL: destination
            )
            return destination
        }

        let firstURL = try matchingURL(
            for: images[pair.firstImage],
            name: "first"
        )
        let secondURL = try matchingURL(
            for: images[pair.secondImage],
            name: "second"
        )

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
        nominalYaws: [Double]? = nil,
        controlPointMasks: [UUID: Data] = [:]
    ) throws -> [PanoramaControlPoint] {
        precondition(nominalYaws == nil || nominalYaws?.count == images.count)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/RingMatching/\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let matchingImages = try images.enumerated().map { index, image in
            guard let mask = controlPointMasks[image.id] else { return image }
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            let destination = temporaryDirectory.appending(
                path: "source-\(index).tif"
            )
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: mask,
                destinationURL: destination
            )
            return replacingURL(of: image, with: destination)
        }
        return try withImagePaths(matchingImages) { paths in
            let bridgeLensModel = bridgeLensModel(
                images: matchingImages,
                horizontalFieldOfView: horizontalFieldOfView,
                lensProfile: lensProfile
            )
            var rawPoints: UnsafeMutablePointer<PWControlPoint>?
            var pointCount: Int32 = 0
            var errorMessage: UnsafeMutablePointer<CChar>?
            let succeeded = nominalYaws?.withUnsafeBufferPointer { yaws in
                PWGenerateRingControlPoints(
                    paths.baseAddress,
                    yaws.baseAddress,
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
                Int32(paths.count),
                horizontalFieldOfView,
                bridgeLensModel,
                &rawPoints,
                &pointCount,
                &errorMessage
            )
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
               images.count == 4,
               horizontalFieldOfView >= 110,
               weakFourImageRingPairs(
                   in: lastPairDiagnostics
               ).isEmpty == false {
                for diagnostic in lastPairDiagnostics {
                    print(
                        "[PanoWizard] CP failure pair "
                            + "\(diagnostic.firstImage)-"
                            + "\(diagnostic.secondImage): selected="
                            + "\(diagnostic.selectedControlPointCount) coverage="
                            + String(format: "%.3f", diagnostic.spatialCoverage)
                    )
                }
                // Four-shot circular-fisheye rings can have a very narrow
                // textured closing overlap. Keep those points until the
                // global bundle adjustment can judge their actual residuals;
                // the engine still rejects sparse transitions that do not
                // become geometrically consistent.
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

    static func weakFourImageRingPairs(
        in diagnostics: [ControlPointPairGenerationDiagnostic]
    ) -> [(Int, Int)] {
        let requiredPairs = [(0, 1), (1, 2), (2, 3), (0, 3)]
        return requiredPairs.filter { first, second in
            guard let diagnostic = diagnostics.first(where: {
                $0.firstImage == first && $0.secondImage == second
            }) else { return true }
            return diagnostic.selectedControlPointCount < 10
                || diagnostic.spatialCoverage < 0.1
        }
    }

    private static func replacingURL(
        of image: SourceImage,
        with url: URL
    ) -> SourceImage {
        SourceImage(
            id: image.id,
            url: url,
            captureDate: image.captureDate,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight,
            cameraModel: image.cameraModel,
            lens: image.lens,
            direction: image.direction,
            role: image.role
        )
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
