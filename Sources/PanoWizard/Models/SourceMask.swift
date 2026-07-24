import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MaskPoint: Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
}

enum SourceMaskRasterizer {
    static func applying(
        stroke: [MaskPoint],
        radius: CGFloat,
        erasing: Bool,
        to existingData: Data?,
        width: Int,
        height: Int
    ) -> Data? {
        guard width > 0, height > 0, !stroke.isEmpty else { return existingData }

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
        context.setStrokeColor(CGColor(red: 1, green: 0.12, blue: 0.08, alpha: 1))
        context.setFillColor(CGColor(red: 1, green: 0.12, blue: 0.08, alpha: 1))
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
}
