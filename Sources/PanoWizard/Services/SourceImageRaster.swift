import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SourceImageRasterError: LocalizedError {
    case unreadableMask
    case rotationFailed

    var errorDescription: String? {
        switch self {
        case .unreadableMask:
            "Masken kunde inte läsas."
        case .rotationFailed:
            "Bilden kunde inte roteras."
        }
    }
}

enum SourceImageRaster {
    static func load(
        _ sourceImage: SourceImage,
        maximumPixelSize: Int
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(
            sourceImage.url as CFURL,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        return rotated(image, by: sourceImage.rotation)
    }

    static func rotatePNGLeft(_ data: Data?) throws -> Data? {
        guard let data else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SourceImageRasterError.unreadableMask
        }
        guard let rotated = rotated(image, by: .left90) else {
            throw SourceImageRasterError.rotationFailed
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            result,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SourceImageRasterError.rotationFailed
        }
        CGImageDestinationAddImage(destination, rotated, [
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw SourceImageRasterError.rotationFailed
        }
        return result as Data
    }

    static func rotated(
        _ image: CGImage,
        by rotation: SourceImage.Rotation
    ) -> CGImage? {
        guard rotation != .none else { return image }
        let swapsDimensions = rotation.swapsDimensions
        let outputWidth = swapsDimensions ? image.height : image.width
        let outputHeight = swapsDimensions ? image.width : image.height
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: outputWidth * 4,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        switch rotation {
        case .none:
            break
        case .left90:
            context.translateBy(x: CGFloat(image.height), y: 0)
            context.rotate(by: .pi / 2)
        case .halfTurn:
            context.translateBy(
                x: CGFloat(image.width),
                y: CGFloat(image.height)
            )
            context.rotate(by: .pi)
        case .right90:
            context.translateBy(x: 0, y: CGFloat(image.width))
            context.rotate(by: -.pi / 2)
        }
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return context.makeImage()
    }
}
