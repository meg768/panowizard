import CoreGraphics
import Foundation

enum LayeredPSDExporter {
    private static let channels: [Int16] = [0, 1, 2, -1]
    private static let sizeLimit = 2_000_000_000

    static func write(
        baseURL: URL,
        compositeURL: URL,
        patches: [(RetouchPatch, URL)],
        adjustments: PanoramaAdjustments,
        maximumWidth: Int,
        to destination: URL
    ) throws {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: work) }

        var base = try RGBAImage(contentsOf: baseURL, maximumWidth: maximumWidth)
        let width = base.width
        let height = base.height
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        guard width <= 30_000, height <= 30_000,
              patches.count < Int(Int16.max),
              width * height * 8 < sizeLimit else { throw tooLarge }
        let settings = adjustments.sanitized

        let channelURL = work.appending(path: "channels")
        try Data().write(to: channelURL)
        let layerChannels = try FileHandle(forWritingTo: channelURL)
        defer { try? layerChannels.close() }
        var layerRecords = Data()

        func writeLayer(_ image: RGBAImage, bounds: CGRect, name: String, visible: Bool) throws {
            let channelLength = Int(bounds.width) * Int(bounds.height) + 2
            let estimate = try Int(layerChannels.offset()) + channelLength * channels.count
                + width * height * 4
            guard estimate < sizeLimit else { throw tooLarge }

            for value in [bounds.minY, bounds.minX, bounds.maxY, bounds.maxX] {
                layerRecords.appendBigEndian(Int32(value))
            }
            layerRecords.appendBigEndian(UInt16(channels.count))
            for channel in channels {
                layerRecords.appendBigEndian(channel)
                layerRecords.appendBigEndian(UInt32(channelLength))
            }
            layerRecords.append(contentsOf: "8BIMnorm".utf8)
            layerRecords.append(contentsOf: [255, 0, visible ? 0 : 2, 0])
            let nameBytes = Array(name.utf8)
            let paddedNameLength = (1 + nameBytes.count + 3) / 4 * 4
            layerRecords.appendBigEndian(UInt32(8 + paddedNameLength))
            layerRecords.appendBigEndian(UInt32(0)) // Layer mask
            layerRecords.appendBigEndian(UInt32(0)) // Blending ranges
            layerRecords.append(UInt8(nameBytes.count))
            layerRecords.append(contentsOf: nameBytes)
            layerRecords.append(Data(count: paddedNameLength - 1 - nameBytes.count))

            for channel in channels.indices {
                try layerChannels.write(contentsOf: Data([0, 0])) // Raw encoding
                try layerChannels.write(contentsOf: image.channelData(channel, in: bounds))
            }
        }

        try adjust(&base, in: canvas, settings: settings)
        try writeLayer(base, bounds: canvas, name: "Panorama", visible: true)
        // The last applied patch is the top layer.
        for (index, entry) in patches.enumerated() {
            let (patch, url) = entry
            var layer = try RetouchPatchService().projectedLayer(
                for: patch, at: url, width: width, height: height
            )
            try adjust(&layer.image, in: layer.bounds, settings: settings)
            try writeLayer(layer.image, bounds: layer.bounds,
                           name: "\(patch.kind.displayName) \(index + 1)", visible: patch.isEnabled)
        }

        var header = Data("8BPS".utf8)
        header.appendBigEndian(UInt16(1))
        header.append(Data(count: 6))
        header.appendBigEndian(UInt16(channels.count))
        header.appendBigEndian(UInt32(height))
        header.appendBigEndian(UInt32(width))
        header.appendBigEndian(UInt16(8))
        header.appendBigEndian(UInt16(3)) // RGB
        header.appendBigEndian(UInt32(0)) // Color mode data

        var resources = Data()
        if let profile = CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() {
            let data = profile as Data
            resources.append(contentsOf: "8BIM".utf8)
            resources.appendBigEndian(UInt16(1039)) // ICC profile
            resources.appendBigEndian(UInt16(0)) // Empty resource name
            resources.appendBigEndian(UInt32(data.count))
            resources.append(data)
            resources.append(Data(count: data.count % 2))
        }
        header.appendBigEndian(UInt32(resources.count))
        header.append(resources)

        let layerInfoLength = 2 + layerRecords.count + (try Int(layerChannels.offset()))
        let padding = layerInfoLength % 2
        let paddedLength = layerInfoLength + padding
        let fileSize = header.count + 12 + paddedLength + 2 + width * height * 4
        guard fileSize <= sizeLimit else { throw tooLarge }
        header.appendBigEndian(UInt32(8 + paddedLength))
        header.appendBigEndian(UInt32(paddedLength))
        header.appendBigEndian(-Int16(patches.count + 1)) // Merged alpha present
        header.append(layerRecords)

        let fileURL = work.appending(path: "panorama.psd")
        try header.write(to: fileURL)
        let output = try FileHandle(forWritingTo: fileURL)
        defer { try? output.close() }
        try output.seekToEnd()
        let channelInput = try FileHandle(forReadingFrom: channelURL)
        defer { try? channelInput.close() }
        while let data = try channelInput.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: data)
        }
        // Layer section padding, zero-length global mask, then raw merged image.
        try output.write(contentsOf: Data(count: padding + 4 + 2))
        if compositeURL != baseURL {
            base = try RGBAImage(contentsOf: compositeURL, maximumWidth: maximumWidth)
            guard base.width == width, base.height == height else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try adjust(&base, in: canvas, settings: settings)
        }
        for channel in channels.indices {
            // PSD stores merged RGB matted on white when a merged alpha channel is present.
            try output.write(contentsOf: base.channelData(channel, in: canvas, matteOnWhite: true))
        }
        try output.close()
        try Data(contentsOf: fileURL, options: .alwaysMapped).write(to: destination, options: .atomic)
    }

    private static var tooLarge: CocoaError {
        CocoaError(.fileWriteUnknown, userInfo: [
            NSLocalizedDescriptionKey: "The panorama is too large for PSD. Choose a smaller size."
        ])
    }

    private static func adjust(
        _ image: inout RGBAImage, in bounds: CGRect, settings: PanoramaAdjustments
    ) throws {
        guard !settings.isNeutral else { return }
        for y in Int(bounds.minY)..<Int(bounds.maxY) {
            try Task.checkCancellation()
            for x in Int(bounds.minX)..<Int(bounds.maxX) {
                let pixel = image.pixel(x: x, y: y)
                guard pixel.a > 0 else { continue }
                let adjusted = PanoramaAdjustmentProcessor.adjusted(
                    Pixel(r: pixel.r / pixel.a, g: pixel.g / pixel.a,
                          b: pixel.b / pixel.a, a: pixel.a),
                    settings: settings
                )
                image.setPixel(Pixel(r: adjusted.r * pixel.a, g: adjusted.g * pixel.a,
                                     b: adjusted.b * pixel.a, a: pixel.a), x: x, y: y)
            }
        }
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
