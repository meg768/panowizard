import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MaskedSourceImageWriter {
    static func write(
        sourceURL: URL,
        maskData: Data?,
        destinationURL: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            throw PanoramaEngineError.stitchingFailed(
                "\(sourceURL.lastPathComponent) kunde inte läsas."
            )
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ), let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PanoramaEngineError.stitchingFailed("Maskbilden kunde inte skapas.")
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        if let maskData {
            guard let maskSource = CGImageSourceCreateWithData(maskData as CFData, nil),
                  let mask = CGImageSourceCreateImageAtIndex(maskSource, 0, nil)
            else {
                throw PanoramaEngineError.stitchingFailed(
                    "Masken för \(sourceURL.lastPathComponent) kunde inte läsas."
                )
            }
            context.setBlendMode(.destinationOut)
            context.draw(mask, in: bounds)
        }
        guard let result = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.tiff.identifier as CFString,
                1,
                nil
              ) else {
            throw PanoramaEngineError.stitchingFailed("Maskbilden kunde inte sparas.")
        }
        CGImageDestinationAddImage(destination, result, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PanoramaEngineError.stitchingFailed("Maskbilden kunde inte sparas.")
        }
    }
}
