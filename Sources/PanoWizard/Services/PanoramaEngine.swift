import Foundation

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
    let nadirRepair: NadirRepairRegistrationResult?
}

enum PanoramaEngineError: LocalizedError {
    case insufficientImages
    case stitchingFailed(String)
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .insufficientImages:
            "Minst två bilder krävs för sammanfogning."
        case .stitchingFailed(let message):
            message
        case .notInstalled:
            "Den nya stitchmotorn byggs separat och är inte inkopplad ännu."
        }
    }
}

struct HuginOpenCVPanoramaEngine: PanoramaEngine {
    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        configuration: StitchingConfiguration,
        cachedRigImageLines: [UUID: String]
    ) async throws -> PanoramaStitchResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.stitchSynchronously(
                panorama,
                masks: masks,
                configuration: configuration
            )
        }.value
    }

    private static func stitchSynchronously(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        configuration: StitchingConfiguration
    ) throws -> PanoramaStitchResult {
        let alignmentImages = panorama.images.filter { $0.role == .alignment }
        let ringImages = alignmentImages.filter { $0.direction == .horizontal }
        let zenithImages = alignmentImages.filter { $0.direction == .zenith }
        let unsupported = alignmentImages.filter { $0.direction == .nadir }
        let fillOnlyImages = panorama.images.filter { $0.role == .fillOnly }
        let nadirRepairImages = fillOnlyImages.filter { $0.direction == .nadir }
        let unsupportedRepairImages = fillOnlyImages.filter {
            $0.direction != .nadir
        }

        guard ringImages.count >= 2 else {
            throw PanoramaEngineError.insufficientImages
        }
        guard zenithImages.count <= 1 else {
            throw PanoramaEngineError.stitchingFailed(
                "Den här första stitchmotorn stöder en zenitbild."
            )
        }
        guard unsupported.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "En nadirbild måste ha bildrollen Reparation."
            )
        }
        guard unsupportedRepairImages.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "I den här etappen kan endast en nadirbild användas som reparation."
            )
        }
        guard nadirRepairImages.count <= 1 else {
            throw PanoramaEngineError.stitchingFailed(
                "I den här etappen stöds en nadirreparation."
            )
        }

        let toolchain = try HuginToolchain.live()
        let workDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "PanoWizard/Stitches/\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )

        let horizontalFieldOfView = initialFieldOfView(configuration)
        let baseProject = workDirectory.appending(path: "01-base.pto")
        let seededProject = workDirectory.appending(path: "02-seeded.pto")
        let controlPointProject = workDirectory.appending(path: "03-points.pto")
        let cleanedRingProject = workDirectory.appending(path: "04-cleaned.pto")
        let optimizedRingProject = workDirectory.appending(path: "05-ring.pto")

        log("Ring feature matching", images: ringImages)
        try toolchain.run(
            "pto_gen",
            arguments: [
                "-p", "3",
                "-f", String(horizontalFieldOfView),
                "-o", baseProject.path()
            ] + ringImages.map { $0.url.path() },
            in: workDirectory
        )
        try HuginProjectFile.seedRing(
            from: baseProject,
            to: seededProject,
            imageCount: ringImages.count
        )
        let ringControlPoints = try OpenCVControlPointMatcher.ring(
            images: ringImages,
            horizontalFieldOfView: horizontalFieldOfView
        )
        try HuginProjectFile.appending(
            controlPoints: ringControlPoints,
            from: seededProject,
            to: controlPointProject
        )

        log("Ring bundle adjustment", images: ringImages)
        try toolchain.run(
            "cpclean",
            arguments: [
                "-o", cleanedRingProject.path(),
                controlPointProject.path()
            ],
            in: workDirectory
        )
        try toolchain.run(
            "autooptimiser",
            arguments: [
                "-a", "-l", "-s",
                "-o", optimizedRingProject.path(),
                cleanedRingProject.path()
            ],
            in: workDirectory
        )

        var finalGeometryProject = optimizedRingProject
        var orderedImages = ringImages
        if let zenith = zenithImages.first {
            log("Frozen-ring zenith registration", images: [zenith])
            let ringOrientations = try HuginProjectFile.orientations(
                in: optimizedRingProject
            )
            let optimizedFieldOfView = try HuginProjectFile
                .horizontalFieldOfView(in: optimizedRingProject)
            let placement = try OpenCVControlPointMatcher.zenith(
                ringImages: ringImages,
                ringOrientations: ringOrientations,
                zenithImage: zenith,
                horizontalFieldOfView: optimizedFieldOfView
            )
            let zenithProject = workDirectory.appending(path: "06-zenith.pto")
            let cleanedZenithProject = workDirectory.appending(
                path: "07-zenith-cleaned.pto"
            )
            let optimizedZenithProject = workDirectory.appending(
                path: "08-geometry.pto"
            )
            try HuginProjectFile.addingZenith(
                image: zenith,
                orientation: placement.orientation,
                controlPoints: placement.controlPoints,
                ringProject: optimizedRingProject,
                destination: zenithProject
            )
            try toolchain.run(
                "cpclean",
                arguments: [
                    "-o", cleanedZenithProject.path(),
                    zenithProject.path()
                ],
                in: workDirectory
            )
            try toolchain.run(
                "autooptimiser",
                arguments: [
                    "-n",
                    "-o", optimizedZenithProject.path(),
                    cleanedZenithProject.path()
                ],
                in: workDirectory
            )
            let frozenRing = try HuginProjectFile.imageLines(
                in: optimizedRingProject
            )
            let resultingRing = Array(
                try HuginProjectFile.imageLines(in: optimizedZenithProject)
                    .prefix(ringImages.count)
            )
            guard frozenRing == resultingRing else {
                throw PanoramaEngineError.stitchingFailed(
                    "Zenitsteget försökte ändra den frysta ringgeometrin."
                )
            }
            finalGeometryProject = optimizedZenithProject
            orderedImages.append(zenith)
        }

        log("Warp and blend", images: orderedImages)
        let preparedDirectory = workDirectory.appending(
            path: "prepared",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: preparedDirectory,
            withIntermediateDirectories: true
        )
        let clipsToCircle = configuration.lensProfile == .sigma8DX
        let preparedImages = try orderedImages.enumerated().map { index, image in
            let destination = preparedDirectory.appending(
                path: "source-\(index).tif"
            )
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: masks[image.id],
                clipsToFisheyeCircle: clipsToCircle,
                destinationURL: destination
            )
            return destination
        }
        let renderSourcesProject = workDirectory.appending(
            path: "09-render-sources.pto"
        )
        try HuginProjectFile.replacingImagePaths(
            in: finalGeometryProject,
            with: preparedImages,
            destination: renderSourcesProject
        )
        let renderProject = workDirectory.appending(path: "10-render.pto")
        try toolchain.run(
            "pano_modify",
            arguments: [
                "-o", renderProject.path(),
                "-p", "2",
                "--fov=360x180",
                "--canvas=4000x2000",
                "--blender=ENBLEND",
                "--ldr-file=JPG",
                "--ldr-compression=92",
                renderSourcesProject.path()
            ],
            in: workDirectory
        )
        let layerPrefix = workDirectory.appending(path: "layer")
        try toolchain.run(
            "nona",
            arguments: [
                "-r", "ldr",
                "-m", "TIFF_m",
                "-o", layerPrefix.path(),
                renderProject.path()
            ],
            in: workDirectory
        )
        let layers = try FileManager.default.contentsOfDirectory(
            at: workDirectory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("layer")
                && ["tif", "tiff"].contains($0.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !layers.isEmpty else {
            throw PanoramaEngineError.stitchingFailed(
                "Hugin skapade inga bildlager."
            )
        }
        let result = workDirectory.appending(path: "panorama.jpg")
        let blendArguments = [
            "-f", "4000x2000+0+0",
            "--wrap=horizontal",
            "--compression=92",
            "--output=\(result.path())"
        ] + layers.map { $0.path() }
        do {
            try toolchain.run(
                "enblend",
                arguments: blendArguments,
                in: workDirectory
            )
        } catch {
            try toolchain.run(
                "enblend",
                arguments: ["--no-optimize"] + blendArguments,
                in: workDirectory
            )
        }

        var nadirRepair: NadirRepairRegistrationResult?
        if let repairImage = nadirRepairImages.first {
            log("Local nadir repair registration", images: [repairImage])
            let overlay = workDirectory.appending(path: "nadir-overlay.png")
            nadirRepair = try OpenCVNadirRepairRegistrar.register(
                panoramaURL: result,
                repairImage: repairImage,
                exclusionMaskData: masks[repairImage.id],
                horizontalFieldOfView: horizontalFieldOfView,
                outputURL: overlay
            )
        }

        return PanoramaStitchResult(
            url: result,
            rigImageLines: [:],
            nadirRepair: nadirRepair
        )
    }

    private static func initialFieldOfView(
        _ configuration: StitchingConfiguration
    ) -> Double {
        switch configuration.lensProfile {
        case .sigma8DX:
            120
        case .nikon105DX:
            100
        case .automatic, .custom:
            configuration.inputHorizontalFieldOfView
        }
    }

    private static func log(_ stage: String, images: [SourceImage]) {
        let names = images.map(\.filename).joined(separator: ", ")
        print("[PanoWizard] \(stage): \(names)")
    }
}
