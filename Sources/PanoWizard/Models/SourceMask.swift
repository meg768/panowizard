import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MaskPoint: Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
}

enum SourceMaskTool: Hashable, Sendable {
    case brush
    case rectangle
}

enum SourceMaskRasterizer {
    struct ExclusionMap: Sendable {
        let width: Int
        let height: Int
        let alpha: [UInt8]

        func contains(_ point: CGPoint, safetyRadius: Int = 24) -> Bool {
            let centerX = Int(point.x.rounded())
            let centerY = height - 1 - Int(point.y.rounded())
            let radiusSquared = safetyRadius * safetyRadius
            let minimumX = max(centerX - safetyRadius, 0)
            let maximumX = min(centerX + safetyRadius, width - 1)
            let minimumY = max(centerY - safetyRadius, 0)
            let maximumY = min(centerY + safetyRadius, height - 1)
            guard minimumX <= maximumX, minimumY <= maximumY else {
                return false
            }
            for y in minimumY...maximumY {
                for x in minimumX...maximumX
                where (x - centerX) * (x - centerX)
                    + (y - centerY) * (y - centerY) <= radiusSquared {
                    if alpha[y * width + x] > 8 {
                        return true
                    }
                }
            }
            return false
        }
    }

    static func exclusionMap(
        from data: Data?,
        width: Int,
        height: Int
    ) -> ExclusionMap? {
        guard let data, width > 0, height > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        var alpha = [UInt8](repeating: 0, count: width * height)
        let rendered = alpha.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress,
                  let context = CGContext(
                    data: address,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        return rendered ? ExclusionMap(
            width: width,
            height: height,
            alpha: alpha
        ) : nil
    }

    static func applying(
        stroke: [MaskPoint],
        radius: CGFloat,
        erasing: Bool,
        controlPointExclusion: Bool = false,
        protectedArea: Bool = false,
        to existingData: Data?,
        width: Int,
        height: Int
    ) -> Data? {
        guard width > 0, height > 0, !stroke.isEmpty else { return existingData }
        if erasing, existingData == nil { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return existingData
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        if let existingData,
           let source = CGImageSourceCreateWithData(existingData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        context.setBlendMode(erasing ? .clear : .normal)
        let color = protectedArea
            ? CGColor(red: 0.08, green: 0.9, blue: 0.22, alpha: 1)
            : controlPointExclusion
                ? CGColor(red: 1, green: 0.55, blue: 0.05, alpha: 1)
                : CGColor(red: 1, green: 0.12, blue: 0.08, alpha: 1)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(radius * 2)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let points = stroke.map {
            CGPoint(x: $0.x * CGFloat(width), y: (1 - $0.y) * CGFloat(height))
        }
        if points.count == 1 {
            let diameter = radius * 2
            context.fillEllipse(
                in: CGRect(
                    x: points[0].x - radius,
                    y: points[0].y - radius,
                    width: diameter,
                    height: diameter
                )
            )
        } else {
            context.beginPath()
            context.move(to: points[0])
            points.dropFirst().forEach { context.addLine(to: $0) }
            context.strokePath()
        }

        guard let image = context.makeImage() else { return existingData }
        if erasing, !hasVisibleAlpha(image) { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return existingData
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return existingData }
        return data as Data
    }

    static func applyingCircle(
        center: MaskPoint,
        radius: CGFloat,
        erasing: Bool,
        controlPointExclusion: Bool = false,
        protectedArea: Bool = false,
        to existingData: Data?,
        width: Int,
        height: Int
    ) -> Data? {
        guard width > 0, height > 0, radius > 0 else { return existingData }
        if erasing, existingData == nil { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return existingData
        }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(canvas)
        if let existingData,
           let source = CGImageSourceCreateWithData(existingData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            context.draw(image, in: canvas)
        }

        context.setBlendMode(erasing ? .clear : .normal)
        let color = protectedArea
            ? CGColor(red: 0.08, green: 0.9, blue: 0.22, alpha: 1)
            : controlPointExclusion
                ? CGColor(red: 1, green: 0.55, blue: 0.05, alpha: 1)
                : CGColor(red: 1, green: 0.12, blue: 0.08, alpha: 1)
        context.setFillColor(color)
        let sourceCenter = CGPoint(
            x: center.x * CGFloat(width),
            y: (1 - center.y) * CGFloat(height)
        )
        context.fillEllipse(in: CGRect(
            x: sourceCenter.x - radius,
            y: sourceCenter.y - radius,
            width: radius * 2,
            height: radius * 2
        ))

        guard let image = context.makeImage() else { return existingData }
        if erasing, !hasVisibleAlpha(image) { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return existingData
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return existingData }
        return data as Data
    }

    static func applyingRectangle(
        from start: MaskPoint,
        to end: MaskPoint,
        erasing: Bool,
        controlPointExclusion: Bool = false,
        protectedArea: Bool = false,
        to existingData: Data?,
        width: Int,
        height: Int
    ) -> Data? {
        guard width > 0, height > 0 else { return existingData }
        if erasing, existingData == nil { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return existingData }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(canvas)
        if let existingData,
           let source = CGImageSourceCreateWithData(existingData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            context.draw(image, in: canvas)
        }
        context.setBlendMode(erasing ? .clear : .normal)
        let color = protectedArea
            ? CGColor(red: 0.08, green: 0.9, blue: 0.22, alpha: 1)
            : controlPointExclusion
                ? CGColor(red: 1, green: 0.55, blue: 0.05, alpha: 1)
                : CGColor(red: 1, green: 0.12, blue: 0.08, alpha: 1)
        context.setFillColor(color)
        let x1 = start.x * CGFloat(width)
        let x2 = end.x * CGFloat(width)
        let y1 = (1 - start.y) * CGFloat(height)
        let y2 = (1 - end.y) * CGFloat(height)
        context.fill(CGRect(
            x: min(x1, x2), y: min(y1, y2),
            width: abs(x2 - x1), height: abs(y2 - y1)
        ))
        guard let image = context.makeImage() else { return existingData }
        if erasing, !hasVisibleAlpha(image) { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return existingData }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return existingData }
        return data as Data
    }

    private static func hasVisibleAlpha(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }
        var alpha = [UInt8](repeating: 0, count: width * height)
        let rendered = alpha.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress,
                  let context = CGContext(
                    data: address,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        return rendered && alpha.contains { $0 > 0 }
    }

    static func inverted(
        _ existingData: Data?,
        width: Int,
        height: Int,
        controlPointExclusion: Bool = false,
        protectedArea: Bool = false
    ) -> Data? {
        var outputWidth = width
        var outputHeight = height
        var existingImage: CGImage?
        if let existingData,
           let source = CGImageSourceCreateWithData(existingData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            existingImage = image
            outputWidth = image.width
            outputHeight = image.height
        }
        guard outputWidth > 0, outputHeight > 0 else { return existingData }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: outputWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return existingData
        }
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: outputWidth,
            height: outputHeight
        )
        let color = protectedArea
            ? CGColor(red: 0.08, green: 0.9, blue: 0.22, alpha: 1)
            : controlPointExclusion
                ? CGColor(red: 1, green: 0.55, blue: 0.05, alpha: 1)
                : CGColor(red: 1, green: 0.12, blue: 0.08, alpha: 1)
        context.setFillColor(color)
        context.fill(bounds)
        if let existingImage {
            context.setBlendMode(.destinationOut)
            context.draw(existingImage, in: bounds)
        }
        guard let image = context.makeImage() else { return existingData }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return existingData
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return existingData
        }
        return data as Data
    }
}
