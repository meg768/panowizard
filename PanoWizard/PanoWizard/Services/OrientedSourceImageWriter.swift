import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OrientedSourceImageWriter {
    static func write(
        sourceImage: SourceImage,
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
            throw PanoramaEngineError.stitchingFailed("The source raster could not be created.")
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        guard let result = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.tiff.identifier as CFString,
                1,
                nil
              ) else {
            throw PanoramaEngineError.stitchingFailed("The source raster could not be saved.")
        }
        CGImageDestinationAddImage(destination, result, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PanoramaEngineError.stitchingFailed("The source raster could not be saved.")
        }
    }
}
