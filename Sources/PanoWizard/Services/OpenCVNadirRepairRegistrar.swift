import Foundation
import CoreGraphics
import ImageIO
import OpenCVBridge

struct NadirRepairRegistrationResult: Sendable {
    let overlayURL: URL
    let placement: NadirRepairPlacement
}

struct PoleControlPointWorkspace: Sendable {
    let repairViewURL: URL
    let ringViewURL: URL
    let points: [DiagnosticControlPoint]
}

enum OpenCVNadirRepairRegistrar {
    static func controlPointWorkspace(
        panoramaURL: URL,
        repairImage: SourceImage,
        horizontalFieldOfView: Double,
        pole: PanoramaPole,
        directory: URL
    ) throws -> PoleControlPointWorkspace {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let (decodedImage, decodedURL) = try decodedWorkingCopy(
            of: repairImage,
            beside: directory.appending(path: "repair.png")
        )
        defer { if let decodedURL { try? FileManager.default.removeItem(at: decodedURL) } }
        let repairURL = directory.appending(path: "repair-local.png")
        let ringURL = directory.appending(path: "ring-local.png")
        var rawPoints: UnsafeMutablePointer<PWControlPoint>?
        var count: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?
        let succeeded = panoramaURL.path.withCString { panoramaPath in
            decodedImage.url.path.withCString { repairPath in
                ringURL.path.withCString { ringPath in
                    repairURL.path.withCString { repairOutputPath in
                        PWGeneratePoleControlPoints(
                            panoramaPath,
                            repairPath,
                            horizontalFieldOfView,
                            pole.pitchDegrees,
                            ringPath,
                            repairOutputPath,
                            &rawPoints,
                            &count,
                            &errorMessage
                        )
                    }
                }
            }
        }
        defer {
            PWFreeControlPoints(rawPoints)
            PWFreeString(errorMessage)
        }
        guard succeeded != 0, let rawPoints else {
            throw PanoramaEngineError.stitchingFailed(
                errorMessage.map { String(cString: $0) }
                    ?? "Kontrollpunkter mot den frysta ringen kunde inte skapas."
            )
        }
        let points = (0..<Int(count)).map { index in
            let point = rawPoints[index]
            return DiagnosticControlPoint(
                firstImage: 0,
                secondImage: 1,
                firstX: point.firstX,
                firstY: point.firstY,
                secondX: point.secondX,
                secondY: point.secondY
            )
        }
        return PoleControlPointWorkspace(
            repairViewURL: repairURL,
            ringViewURL: ringURL,
            points: points
        )
    }

    static func placement(
        bySolving points: [DiagnosticControlPoint],
        from placement: NadirRepairPlacement
    ) throws -> (NadirRepairPlacement, [DiagnosticControlPoint]) {
        var cPoints = points.map {
            PWControlPoint(
                firstImage: 0,
                secondImage: 1,
                firstX: $0.firstX,
                firstY: $0.firstY,
                secondX: $0.secondX,
                secondY: $0.secondY
            )
        }
        var registration = PWNadirRegistration()
        var errors = [Double](repeating: 0, count: points.count)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let succeeded = cPoints.withUnsafeMutableBufferPointer { buffer in
            errors.withUnsafeMutableBufferPointer { errorBuffer in
                PWSolvePoleControlPoints(
                    buffer.baseAddress,
                    Int32(buffer.count),
                    &registration,
                    errorBuffer.baseAddress,
                    &errorMessage
                )
            }
        }
        defer { PWFreeString(errorMessage) }
        guard succeeded != 0 else {
            throw PanoramaEngineError.stitchingFailed(
                errorMessage.map { String(cString: $0) }
                    ?? "Polbilden kunde inte anpassas till kontrollpunkterna."
            )
        }
        var updated = placement
        updated.localHomography = [
            registration.h00, registration.h01, registration.h02,
            registration.h10, registration.h11, registration.h12,
            registration.h20, registration.h21, registration.h22
        ]
        updated.manualAdjustment = .identity
        updated.blendedPreview = false
        updated.controlPoints = zip(points, errors).map { point, error in
            var point = point
            point.error = error
            return point
        }
        return (updated, updated.controlPoints ?? [])
    }
    static func register(
        panoramaURL: URL,
        repairImage: SourceImage,
        exclusionMaskData: Data?,
        horizontalFieldOfView: Double,
        pole: PanoramaPole = .nadir,
        outputURL: URL
    ) throws -> NadirRepairRegistrationResult {
        let (repairImage, decodedURL) = try decodedWorkingCopy(
            of: repairImage,
            beside: outputURL
        )
        defer {
            if let decodedURL {
                try? FileManager.default.removeItem(at: decodedURL)
            }
        }
        let maskURL = try temporaryMaskURL(
            for: exclusionMaskData,
            beside: outputURL
        )
        defer {
            if let maskURL {
                try? FileManager.default.removeItem(at: maskURL)
            }
        }

        var registration = PWNadirRegistration()
        var errorMessage: UnsafeMutablePointer<CChar>?
        let succeeded = panoramaURL.path.withCString { panoramaPath in
            repairImage.url.path.withCString { repairPath in
                (maskURL?.path ?? "").withCString { maskPath in
                    outputURL.path.withCString { outputPath in
                        PWRegisterNadirRepair(
                            panoramaPath,
                            repairPath,
                            maskPath,
                            horizontalFieldOfView,
                            pole.pitchDegrees,
                            outputPath,
                            &registration,
                            &errorMessage
                        )
                    }
                }
            }
        }
        defer {
            PWFreeString(errorMessage)
        }
        guard succeeded != 0 else {
            let message = errorMessage.map { String(cString: $0) }
                ?? "Nadirbilden kunde inte positioneras."
            throw PanoramaEngineError.stitchingFailed(message)
        }

        let homography = [
            registration.h00,
            registration.h01,
            registration.h02,
            registration.h10,
            registration.h11,
            registration.h12,
            registration.h20,
            registration.h21,
            registration.h22
        ]
        return NadirRepairRegistrationResult(
            overlayURL: outputURL,
            placement: NadirRepairPlacement(
                imageID: repairImage.id,
                localHomography: homography,
                matchedFeatureCount: Int(registration.matchedFeatureCount),
                localViewFieldOfView: registration.localViewFieldOfView,
                contentBounds: alphaContentBounds(at: outputURL)
            )
        )
    }

    static func renderOverlay(
        repairImage: SourceImage,
        exclusionMaskData: Data?,
        horizontalFieldOfView: Double,
        placement: NadirRepairPlacement,
        outputURL: URL
    ) throws {
        let (repairImage, decodedURL) = try decodedWorkingCopy(
            of: repairImage,
            beside: outputURL
        )
        defer {
            if let decodedURL {
                try? FileManager.default.removeItem(at: decodedURL)
            }
        }
        let maskURL = try temporaryMaskURL(
            for: exclusionMaskData,
            beside: outputURL
        )
        defer {
            if let maskURL {
                try? FileManager.default.removeItem(at: maskURL)
            }
        }

        var registration = cRegistration(from: placement)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let succeeded = repairImage.url.path.withCString { repairPath in
            (maskURL?.path ?? "").withCString { maskPath in
                outputURL.path.withCString { outputPath in
                    PWRenderNadirRepairOverlay(
                        repairPath,
                        maskPath,
                        horizontalFieldOfView,
                        &registration,
                        outputPath,
                        &errorMessage
                    )
                }
            }
        }
        defer {
            PWFreeString(errorMessage)
        }
        guard succeeded != 0 else {
            let message = errorMessage.map { String(cString: $0) }
                ?? "Nadirlagret kunde inte uppdateras."
            throw PanoramaEngineError.stitchingFailed(message)
        }
    }

    static func renderBlendedOverlay(
        panoramaURL: URL,
        repairImage: SourceImage,
        exclusionMaskData: Data?,
        horizontalFieldOfView: Double,
        pole: PanoramaPole = .nadir,
        placement: NadirRepairPlacement,
        outputURL: URL
    ) throws {
        let (repairImage, decodedURL) = try decodedWorkingCopy(
            of: repairImage,
            beside: outputURL
        )
        defer {
            if let decodedURL {
                try? FileManager.default.removeItem(at: decodedURL)
            }
        }
        let toolchain = try HuginToolchain.live()
        let workDirectory = outputURL
            .deletingLastPathComponent()
            .appending(
                path: "Enblend-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: workDirectory)
        }

        let maskURL = try temporaryMaskURL(
            for: exclusionMaskData,
            beside: outputURL
        )
        defer {
            if let maskURL {
                try? FileManager.default.removeItem(at: maskURL)
            }
        }

        let baseLayerURL = workDirectory.appending(path: "base.tif")
        let repairLayerURL = workDirectory.appending(path: "repair.tif")
        let blendedLocalURL = workDirectory.appending(path: "blended.tif")
        let adjustment = placement.manualAdjustment ?? .identity
        var cornerOffsets = adjustment.resolvedCornerOffsets
        var contentBounds = placement.resolvedContentBounds
        var registration = cRegistration(from: placement)
        var preparationError: UnsafeMutablePointer<CChar>?
        let prepared = panoramaURL.path.withCString { panoramaPath in
            repairImage.url.path.withCString { repairPath in
                (maskURL?.path ?? "").withCString { maskPath in
                    baseLayerURL.path.withCString { basePath in
                        repairLayerURL.path.withCString { repairOutputPath in
                            cornerOffsets.withUnsafeMutableBufferPointer { offsets in
                                contentBounds.withUnsafeMutableBufferPointer { bounds in
                                    PWPrepareNadirRepairBlend(
                                        panoramaPath,
                                        repairPath,
                                        maskPath,
                                        horizontalFieldOfView,
                                        pole.pitchDegrees,
                                        &registration,
                                        adjustment.translationX,
                                        adjustment.translationY,
                                        adjustment.rotationDegrees,
                                        adjustment.scale,
                                        offsets.baseAddress,
                                        bounds.baseAddress,
                                        basePath,
                                        repairOutputPath,
                                        &preparationError
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        defer {
            PWFreeString(preparationError)
        }
        guard prepared != 0 else {
            let message = preparationError.map { String(cString: $0) }
                ?? "Nadirreparationen kunde inte förberedas för Enblend."
            throw PanoramaEngineError.stitchingFailed(message)
        }

        let blendArguments = [
            "--fine-mask",
            "--blend-colorspace=CIELAB",
            "--compression=deflate",
            "-f", "1600x1600+0+0",
            "--output=\(blendedLocalURL.path(percentEncoded: false))",
            baseLayerURL.path(percentEncoded: false),
            repairLayerURL.path(percentEncoded: false)
        ]
        do {
            try toolchain.run(
                "enblend",
                arguments: blendArguments,
                in: workDirectory
            )
        } catch {
            try? FileManager.default.removeItem(at: blendedLocalURL)
            try toolchain.run(
                "enblend",
                arguments: ["--no-optimize"] + blendArguments,
                in: workDirectory
            )
        }

        var finishingError: UnsafeMutablePointer<CChar>?
        let finished = blendedLocalURL.path.withCString { blendedPath in
            outputURL.path.withCString { outputPath in
                PWFinishNadirRepairBlend(
                    blendedPath,
                    outputPath,
                    &finishingError
                )
            }
        }
        defer {
            PWFreeString(finishingError)
        }
        guard finished != 0 else {
            let message = finishingError.map { String(cString: $0) }
                ?? "Enblends nadirresultat kunde inte göras till en förhandsvisning."
            throw PanoramaEngineError.stitchingFailed(message)
        }
    }

    private static func cRegistration(
        from placement: NadirRepairPlacement
    ) -> PWNadirRegistration {
        let homography = placement.localHomography
        return PWNadirRegistration(
            h00: homography[0],
            h01: homography[1],
            h02: homography[2],
            h10: homography[3],
            h11: homography[4],
            h12: homography[5],
            h20: homography[6],
            h21: homography[7],
            h22: homography[8],
            matchedFeatureCount: Int32(placement.matchedFeatureCount),
            localViewFieldOfView: placement.localViewFieldOfView
        )
    }

    static func alphaContentBounds(at url: URL) -> [Double]? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        return [
            Double(minimumX) / Double(width),
            Double(minimumY) / Double(height),
            Double(maximumX - minimumX + 1) / Double(width),
            Double(maximumY - minimumY + 1) / Double(height)
        ]
    }

    private static func decodedWorkingCopy(
        of image: SourceImage,
        beside outputURL: URL
    ) throws -> (SourceImage, URL?) {
        let rawExtensions = [
            "nef", "nrw", "cr2", "cr3", "arw", "dng", "raf", "orf", "rw2"
        ]
        guard rawExtensions.contains(image.url.pathExtension.lowercased()) else {
            return (image, nil)
        }
        let url = outputURL.deletingLastPathComponent().appending(
            path: "\(UUID().uuidString)-decoded-source.tif"
        )
        try MaskedSourceImageWriter.write(
            sourceURL: image.url,
            maskData: nil,
            clipsToFisheyeCircle: false,
            destinationURL: url
        )
        return (
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
            ),
            url
        )
    }

    private static func temporaryMaskURL(
        for data: Data?,
        beside outputURL: URL
    ) throws -> URL? {
        guard let data else { return nil }
        let url = outputURL
            .deletingLastPathComponent()
            .appending(path: "\(UUID().uuidString)-exclusion-mask.png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
