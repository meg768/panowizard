import Foundation
import CoreGraphics
import ImageIO
import OpenCVBridge

struct NadirRepairRegistrationResult: Sendable {
    let overlayURL: URL
    let placement: NadirRepairPlacement
}

enum OpenCVNadirRepairRegistrar {
    static func alignmentToProjectedOverlay(
        at projectedOverlayURL: URL,
        repairImage: SourceImage,
        exclusionMaskData: Data?,
        horizontalFieldOfView: Double
    ) throws -> (homography: [Double], matchedFeatureCount: Int) {
        let (repairImage, decodedURL) = try decodedWorkingCopy(
            of: repairImage,
            beside: projectedOverlayURL
        )
        defer {
            if let decodedURL {
                try? FileManager.default.removeItem(at: decodedURL)
            }
        }
        let maskURL = try temporaryMaskURL(
            for: exclusionMaskData,
            beside: projectedOverlayURL
        )
        defer {
            if let maskURL {
                try? FileManager.default.removeItem(at: maskURL)
            }
        }

        var registration = PWNadirRegistration()
        var errorMessage: UnsafeMutablePointer<CChar>?
        let succeeded = projectedOverlayURL.path.withCString { overlayPath in
            repairImage.url.path.withCString { repairPath in
                (maskURL?.path ?? "").withCString { maskPath in
                    PWAlignNadirRepairToProjectedOverlay(
                        overlayPath,
                        repairPath,
                        maskPath,
                        horizontalFieldOfView,
                        &registration,
                        &errorMessage
                    )
                }
            }
        }
        defer { PWFreeString(errorMessage) }
        guard succeeded != 0 else {
            throw PanoramaEngineError.stitchingFailed(
                errorMessage.map { String(cString: $0) }
                    ?? "Polbildens sfäriska projektion kunde inte återanvändas."
            )
        }
        return (
            [
                registration.h00, registration.h01, registration.h02,
                registration.h10, registration.h11, registration.h12,
                registration.h20, registration.h21, registration.h22
            ],
            Int(registration.matchedFeatureCount)
        )
    }

    static func extractPoleOverlay(
        from equirectangularLayer: URL,
        pole: PanoramaPole,
        outputURL: URL
    ) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let succeeded = equirectangularLayer.path.withCString { layerPath in
            outputURL.path.withCString { outputPath in
                PWExtractPoleOverlay(
                    layerPath,
                    pole.pitchDegrees,
                    outputPath,
                    &errorMessage
                )
            }
        }
        defer { PWFreeString(errorMessage) }
        guard succeeded != 0 else {
            throw PanoramaEngineError.stitchingFailed(
                errorMessage.map { String(cString: $0) }
                    ?? "Hugins pollager kunde inte projiceras."
            )
        }
    }

    static func warpPoleOverlay(
        at sourceURL: URL,
        using placement: NadirRepairPlacement,
        outputURL: URL
    ) throws {
        var registration = cRegistration(from: placement)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let succeeded = sourceURL.path.withCString { sourcePath in
            outputURL.path.withCString { outputPath in
                PWWarpPoleOverlay(
                    sourcePath,
                    &registration,
                    outputPath,
                    &errorMessage
                )
            }
        }
        defer { PWFreeString(errorMessage) }
        guard succeeded != 0 else {
            throw PanoramaEngineError.stitchingFailed(
                errorMessage.map { String(cString: $0) }
                    ?? "Polbildens perspektiv kunde inte justeras."
            )
        }
    }
    static func localPoleCoordinate(
        panoramaPoint: CGPoint,
        panoramaSize: CGSize,
        pole: PanoramaPole
    ) -> CGPoint? {
        let longitude = panoramaPoint.x / panoramaSize.width * 2 * .pi - .pi
        let latitude = .pi / 2 - panoramaPoint.y / panoramaSize.height * .pi
        let worldX = sin(longitude) * cos(latitude)
        let worldY = -sin(latitude)
        let worldZ = cos(longitude) * cos(latitude)
        let pitch = pole.pitchDegrees * .pi / 180
        let cameraX = worldX
        let cameraY = cos(pitch) * worldY + sin(pitch) * worldZ
        let cameraZ = -sin(pitch) * worldY + cos(pitch) * worldZ
        guard cameraZ > 1e-7 else { return nil }
        let center = 800.0
        let focal = center / tan(60 * .pi / 180)
        return CGPoint(
            x: center + focal * cameraX / cameraZ,
            y: center + focal * cameraY / cameraZ
        )
    }

    static func coarseSimilarityPlacement(
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
                PWSolvePoleSimilarity(
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
                    ?? "Polbildens grova skala kunde inte bestämmas."
            )
        }
        var updated = placement
        updated.localHomography = [
            registration.h00, registration.h01, registration.h02,
            registration.h10, registration.h11, registration.h12,
            registration.h20, registration.h21, registration.h22
        ]
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
                sourceHorizontalFieldOfView: horizontalFieldOfView
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
        projectedRepairURL: URL? = nil,
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
        let seamMaskTemplate = workDirectory.appending(
            path: "seam-mask-%n.tif"
        )
        var registration = cRegistration(from: placement)
        var preparationError: UnsafeMutablePointer<CChar>?
        let prepared = panoramaURL.path.withCString { panoramaPath in
            repairImage.url.path.withCString { repairPath in
                (maskURL?.path ?? "").withCString { maskPath in
                    (projectedRepairURL?.path ?? "").withCString {
                        projectedRepairPath in
                        baseLayerURL.path.withCString { basePath in
                            repairLayerURL.path.withCString { repairOutputPath in
                                PWPrepareNadirRepairBlend(
                                    panoramaPath,
                                    repairPath,
                                    maskPath,
                                    projectedRepairPath,
                                    horizontalFieldOfView,
                                    pole.pitchDegrees,
                                    &registration,
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
        defer {
            PWFreeString(preparationError)
        }
        guard prepared != 0 else {
            let message = preparationError.map { String(cString: $0) }
                ?? "Nadirreparationen kunde inte förberedas för Enblend."
            throw PanoramaEngineError.stitchingFailed(message)
        }

        let blendArguments = [
            "--primary-seam-generator=nearest-feature-transform",
            "--fine-mask",
            "--save-masks=\(seamMaskTemplate.path(percentEncoded: false))",
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
            for url in try FileManager.default.contentsOfDirectory(
                at: workDirectory,
                includingPropertiesForKeys: nil
            ) where url.lastPathComponent.hasPrefix("seam-mask-") {
                try? FileManager.default.removeItem(at: url)
            }
            try toolchain.run(
                "enblend",
                arguments: ["--no-optimize"] + blendArguments,
                in: workDirectory
            )
        }

        let seamMasks = try FileManager.default.contentsOfDirectory(
            at: workDirectory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("seam-mask-")
                && ["tif", "tiff"].contains($0.pathExtension.lowercased())
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare(
                $1.lastPathComponent
            ) == .orderedAscending
        }
        guard let repairSeamMaskURL = seamMasks.last else {
            throw PanoramaEngineError.stitchingFailed(
                "Enblend skapade ingen sömmask för reparationsbilden."
            )
        }

        var finishingError: UnsafeMutablePointer<CChar>?
        let finished = blendedLocalURL.path.withCString { blendedPath in
            repairLayerURL.path.withCString { repairPath in
                repairSeamMaskURL.path.withCString { seamMaskPath in
                    outputURL.path.withCString { outputPath in
                        PWFinishNadirRepairBlend(
                            blendedPath,
                            repairPath,
                            seamMaskPath,
                            outputPath,
                            &finishingError
                        )
                    }
                }
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
