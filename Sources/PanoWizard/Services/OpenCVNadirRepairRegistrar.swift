import Foundation
import OpenCVBridge

struct NadirRepairRegistrationResult: Sendable {
    let overlayURL: URL
    let placement: NadirRepairPlacement
}

enum OpenCVNadirRepairRegistrar {
    static func register(
        panoramaURL: URL,
        repairImage: SourceImage,
        exclusionMaskData: Data?,
        horizontalFieldOfView: Double,
        outputURL: URL
    ) throws -> NadirRepairRegistrationResult {
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
                localViewFieldOfView: registration.localViewFieldOfView
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
        placement: NadirRepairPlacement,
        outputURL: URL
    ) throws {
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
        var registration = cRegistration(from: placement)
        var preparationError: UnsafeMutablePointer<CChar>?
        let prepared = panoramaURL.path.withCString { panoramaPath in
            repairImage.url.path.withCString { repairPath in
                (maskURL?.path ?? "").withCString { maskPath in
                    baseLayerURL.path.withCString { basePath in
                        repairLayerURL.path.withCString { repairOutputPath in
                            PWPrepareNadirRepairBlend(
                                panoramaPath,
                                repairPath,
                                maskPath,
                                horizontalFieldOfView,
                                &registration,
                                adjustment.translationX,
                                adjustment.translationY,
                                adjustment.rotationDegrees,
                                adjustment.scale,
                                basePath,
                                repairOutputPath,
                                &preparationError
                            )
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
            "--output=\(blendedLocalURL.path())",
            baseLayerURL.path(),
            repairLayerURL.path()
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
