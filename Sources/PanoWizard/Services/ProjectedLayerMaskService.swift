import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ProjectedLayerMaskService {
    static let width = 4000
    static let height = 2000

    static func normalize(
        _ sourceURL: URL,
        exclusionMask: Data? = nil,
        insetsAlphaByOnePixel: Bool = false,
        to destinationURL: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let context = rgbaContext() else {
            throw PanoramaEngineError.stitchingFailed(
                "Ett projicerat bildlager kunde inte läsas."
            )
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary]
            as? [CFString: Any] ?? [:]
        let xResolution = (tiff[kCGImagePropertyTIFFXResolution] as? NSNumber)?
            .doubleValue ?? 1
        let yResolution = (tiff[kCGImagePropertyTIFFYResolution] as? NSNumber)?
            .doubleValue ?? 1
        let x = Int((((tiff[kCGImagePropertyTIFFXPosition] as? NSNumber)?
            .doubleValue ?? 0) * xResolution).rounded())
        let y = Int((((tiff[kCGImagePropertyTIFFYPosition] as? NSNumber)?
            .doubleValue ?? 0) * yResolution).rounded())
        context.draw(image, in: CGRect(
            x: x,
            y: height - y - image.height,
            width: image.width,
            height: image.height
        ))
        if let exclusionMask,
           let mask = maskImage(from: exclusionMask) {
            context.setBlendMode(.destinationOut)
            context.draw(mask, in: bounds)
        }
        if insetsAlphaByOnePixel {
            insetAlphaByOnePixel(in: context)
        }
        try write(context.makeImage(), to: destinationURL)
    }

    static func insetAlphaByOnePixel(
        _ alpha: [UInt8],
        width: Int,
        height: Int
    ) -> [UInt8] {
        guard width > 0, height > 0, alpha.count == width * height else {
            return alpha
        }
        var result = alpha
        for y in 0..<height {
            let firstY = max(0, y - 1)
            let lastY = min(height - 1, y + 1)
            for x in 0..<width {
                let firstX = max(0, x - 1)
                let lastX = min(width - 1, x + 1)
                var minimum = UInt8.max
                for neighborY in firstY...lastY {
                    for neighborX in firstX...lastX {
                        minimum = min(
                            minimum,
                            alpha[neighborY * width + neighborX]
                        )
                    }
                }
                result[y * width + x] = minimum
            }
        }
        return result
    }

    static func alphaMask(from normalizedLayer: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(normalizedLayer as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let input = rgbaContext() else {
            throw PanoramaEngineError.stitchingFailed(
                "Objektskyddet kunde inte projiceras."
            )
        }
        input.draw(image, in: bounds)
        guard let bytes = input.data else {
            throw PanoramaEngineError.stitchingFailed("Objektskyddet saknar alfa.")
        }
        let sourceBytes = bytes.assumingMemoryBound(to: UInt8.self)
        var outputBytes = [UInt8](repeating: 0, count: width * height * 4)
        let madeImage = outputBytes.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let base = bytes.baseAddress else { return nil }
            let target = base.assumingMemoryBound(to: UInt8.self)
            for pixel in 0..<(width * height) {
                let alpha = sourceBytes[pixel * 4 + 3]
                target[pixel * 4 + 1] = alpha
                target[pixel * 4 + 3] = alpha
            }
            let context = CGContext(
                data: base, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return context?.makeImage()
        }
        return try pngData(madeImage)
    }

    static func merged(_ masks: [Data]) throws -> Data? {
        guard !masks.isEmpty, let context = rgbaContext() else { return nil }
        for data in masks {
            if let mask = maskImage(from: data) { context.draw(mask, in: bounds) }
        }
        return try pngData(context.makeImage())
    }

    private static var bounds: CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    private static func rgbaContext() -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func insetAlphaByOnePixel(in context: CGContext) {
        guard let data = context.data else { return }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let pixelCount = width * height
        var alpha = [UInt8](repeating: 0, count: pixelCount)
        for pixel in 0..<pixelCount {
            alpha[pixel] = pixels[pixel * 4 + 3]
        }
        let inset = insetAlphaByOnePixel(alpha, width: width, height: height)
        for pixel in 0..<pixelCount {
            let oldAlpha = alpha[pixel]
            let newAlpha = inset[pixel]
            guard newAlpha < oldAlpha else { continue }
            let byte = pixel * 4
            if oldAlpha == 0 {
                pixels[byte] = 0
                pixels[byte + 1] = 0
                pixels[byte + 2] = 0
            } else {
                for channel in 0..<3 {
                    pixels[byte + channel] = UInt8(
                        Int(pixels[byte + channel]) * Int(newAlpha)
                            / Int(oldAlpha)
                    )
                }
            }
            pixels[byte + 3] = newAlpha
        }
    }

    private static func maskImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pngData(_ image: CGImage?) throws -> Data {
        guard let image else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }

    private static func write(_ image: CGImage?, to url: URL) throws {
        guard let image,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.tiff.identifier as CFString, 1, nil
              ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
