import CryptoKit
import Foundation
import OpenCVBridge

struct TrialOpenCVPanoramaEngine: PanoramaEngine {
    static let outputWidth = 4096
    static let cacheVersion = "trial-native-weak-crosslink-v1"

    func stitch(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> PanoramaStitchResult {
        let context = TrialExecutionContext(progress: progress)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Self.stitchSynchronously(
                    panorama,
                    masks: masks,
                    protectedMasks: protectedMasks,
                    context: context
                )
            }.value
        } onCancel: {
            context.cancel()
        }
    }

    static func sourceImages(in panorama: PanoramaSet) -> [SourceImage] {
        panorama.images.filter(\.isEnabled)
    }

    private static func stitchSynchronously(
        _ panorama: PanoramaSet,
        masks: [UUID: Data],
        protectedMasks: [UUID: Data],
        context: TrialExecutionContext
    ) throws -> PanoramaStitchResult {
        let images = sourceImages(in: panorama)
        guard images.count >= 2 else {
            throw PanoramaEngineError.insufficientImages
        }

        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory.appending(
            path: "PanoWizard/Trial/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: workDirectory) }

        var sourceURLs: [URL] = []
        var protectedURLs: [URL?] = []
        for (index, image) in images.enumerated() {
            try context.checkCancellation()
            context.report(
                Double(index) / Double(images.count) * 0.08,
                "Förbereder källbilder…"
            )
            let sourceURL = workDirectory.appending(path: "source-\(index).tif")
            try MaskedSourceImageWriter.write(
                sourceURL: image.url,
                maskData: masks[image.id],
                destinationURL: sourceURL
            )
            sourceURLs.append(sourceURL)

            if let data = protectedMasks[image.id] {
                let maskURL = workDirectory.appending(path: "protected-\(index).png")
                try data.write(to: maskURL, options: .atomic)
                protectedURLs.append(maskURL)
            } else {
                protectedURLs.append(nil)
            }
        }

        let outputURL = workDirectory.appending(path: "panorama.jpg")
        let cacheURL = try alignmentCacheURL(images: images, masks: masks)
        let compositionRoles = images.map { image -> UInt8 in
            if image.effectiveRole == .fillOnly { return 2 }
            if image.role == .alignment || image.automaticRole == .alignment {
                return 1
            }
            return 0
        }
        var report = PWTrialStitchReport()
        var errorPointer: UnsafeMutablePointer<CChar>?
        let opaqueContext = Unmanaged.passUnretained(context).toOpaque()
        let succeeded = sourceURLs.map { $0.path(percentEncoded: false) }
            .withCStringArray { sourcePaths in
                protectedURLs.map { $0?.path(percentEncoded: false) }
                    .withOptionalCStringArray { protectedPaths in
                        compositionRoles.withUnsafeBufferPointer { roles in
                            PWStitchTrialPanorama(
                                sourcePaths,
                                protectedPaths,
                                roles.baseAddress,
                                Int32(sourceURLs.count),
                                cacheURL.path(percentEncoded: false),
                                outputURL.path(percentEncoded: false),
                                Int32(outputWidth),
                                opaqueContext,
                                trialProgressCallback,
                                trialCancellationCallback,
                                &report,
                                &errorPointer
                            )
                        }
                    }
            }
        defer { PWFreeString(errorPointer) }
        if context.isCancelled {
            throw CancellationError()
        }
        guard succeeded != 0 else {
            throw PanoramaEngineError.stitchingFailed(
                errorPointer.map { String(cString: $0) }
                    ?? "Panoramamotorn misslyckades."
            )
        }
        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw PanoramaEngineError.stitchingFailed(
                "Panoramamotorn skapade ingen panoramabild."
            )
        }

        let retainedURL = fileManager.temporaryDirectory.appending(
            path: "PanoWizard/Results/\(UUID().uuidString).jpg"
        )
        try fileManager.createDirectory(
            at: retainedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: outputURL, to: retainedURL)
        context.report(1, "Panoramat är klart")
        return PanoramaStitchResult(
            url: retainedURL,
            coveragePercent: report.coveragePercent,
            holeCount: Int(report.holeCount),
            usedAlignmentCache: report.usedAlignmentCache != 0
        )
    }

    private static func alignmentCacheURL(
        images: [SourceImage],
        masks: [UUID: Data]
    ) throws -> URL {
        var digest = SHA256()
        digest.update(data: Data(cacheVersion.utf8))
        let fileManager = FileManager.default
        for image in images {
            digest.update(data: Data(image.id.uuidString.utf8))
            digest.update(data: Data(image.url.path(percentEncoded: false).utf8))
            digest.update(data: Data(image.effectiveRole.rawValue.utf8))
            digest.update(data: Data(image.direction.rawValue.utf8))
            let attributes = try fileManager.attributesOfItem(
                atPath: image.url.path(percentEncoded: false)
            )
            if let size = attributes[.size] as? NSNumber {
                digest.update(data: Data(size.stringValue.utf8))
            }
            if let date = attributes[.modificationDate] as? Date {
                digest.update(data: Data(String(date.timeIntervalSince1970).utf8))
            }
            if let mask = masks[image.id] {
                digest.update(data: mask)
            }
        }
        let key = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let base = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(
            path: "PanoWizard/TrialAlignment",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "alignment-\(key).yml")
    }
}

private final class TrialExecutionContext: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let progress: @Sendable (Double, String) -> Void

    init(progress: @escaping @Sendable (Double, String) -> Void) {
        self.progress = progress
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
    }

    func report(_ fraction: Double, _ stage: String) {
        progress(min(max(fraction, 0), 1), stage)
    }
}

private let trialProgressCallback: PWTrialProgressCallback = {
    context, stage, fraction in
    guard let context else { return }
    let execution = Unmanaged<TrialExecutionContext>
        .fromOpaque(context)
        .takeUnretainedValue()
    execution.report(
        fraction,
        stage.map { String(cString: $0) } ?? "Sammanfogar panorama…"
    )
}

private let trialCancellationCallback: PWTrialCancellationCallback = { context in
    guard let context else { return 0 }
    let execution = Unmanaged<TrialExecutionContext>
        .fromOpaque(context)
        .takeUnretainedValue()
    return execution.isCancelled ? 1 : 0
}

private extension Array where Element == String {
    func withCStringArray<Result>(
        _ body: (UnsafePointer<UnsafePointer<CChar>?>) throws -> Result
    ) rethrows -> Result {
        let allocations = map { strdup($0) }
        defer { allocations.forEach { free($0) } }
        let pointers: [UnsafePointer<CChar>?] = allocations.map {
            $0.map { UnsafePointer($0) }
        }
        return try pointers.withUnsafeBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }
}

private extension Array where Element == String? {
    func withOptionalCStringArray<Result>(
        _ body: (UnsafePointer<UnsafePointer<CChar>?>) throws -> Result
    ) rethrows -> Result {
        let allocations: [UnsafeMutablePointer<CChar>?] = map { value in
            value.flatMap { strdup($0) }
        }
        defer { allocations.forEach { free($0) } }
        let pointers: [UnsafePointer<CChar>?] = allocations.map {
            $0.map { UnsafePointer($0) }
        }
        return try pointers.withUnsafeBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }
}
