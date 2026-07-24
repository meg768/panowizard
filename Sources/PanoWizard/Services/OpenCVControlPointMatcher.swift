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

enum OpenCVControlPointMatcher {
    static func ring(
        images: [SourceImage],
        horizontalFieldOfView: Double
    ) throws -> [PanoramaControlPoint] {
        try withImagePaths(images) { paths in
            var rawPoints: UnsafeMutablePointer<PWControlPoint>?
            var pointCount: Int32 = 0
            var errorMessage: UnsafeMutablePointer<CChar>?
            let succeeded = PWGenerateRingControlPoints(
                paths.baseAddress,
                Int32(paths.count),
                horizontalFieldOfView,
                &rawPoints,
                &pointCount,
                &errorMessage
            )
            return try result(
                succeeded: succeeded,
                rawPoints: rawPoints,
                pointCount: pointCount,
                errorMessage: errorMessage
            )
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
}
