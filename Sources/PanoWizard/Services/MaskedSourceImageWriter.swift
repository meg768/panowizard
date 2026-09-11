import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MaskedSourceImageWriter {
    static func write(
        sourceImage: SourceImage,
        maskData: Data?,
        destinationURL: URL
    ) throws {
        guard let image = SourceImageRaster.load(
            sourceImage,
            maximumPixelSize: max(
                sourceImage.pixelWidth,
                sourceImage.pixelHeight
            )
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
                    "Masken för \(sourceImage.filename) kunde inte läsas."
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
