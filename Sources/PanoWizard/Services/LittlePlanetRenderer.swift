import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LittlePlanetProjection: String, CaseIterable, Sendable {
    case stereographic = "Stereografisk"
}

enum LittlePlanetBackground: String, CaseIterable, Sendable {
    case transparent = "Transparent"
    case black = "Svart"
    case white = "Vit"
}

struct LittlePlanetSettings: Equatable, Sendable {
    var projection = LittlePlanetProjection.stereographic
    var rotationDegrees = 0.0
    var zoomPercent = 100.0
    var horizonPercent = 50.0
    var background = LittlePlanetBackground.transparent
}

struct LittlePlanetSource: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(url: URL) throws {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { throw CocoaError(.fileReadCorruptFile) }

        width = image.width
        height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { throw CocoaError(.fileReadCorruptFile) }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.pixels = pixels
    }
}

enum LittlePlanetRenderer {
    static func render(
        source: LittlePlanetSource,
        side: Int,
        settings: LittlePlanetSettings
    ) throws -> CGImage {
        guard side > 0 else { throw CocoaError(.fileWriteUnknown) }
        var output = [UInt8](repeating: 0, count: side * side * 4)
        let center = Double(side) / 2.0
        let radius = Double(side) * 0.46 * settings.zoomPercent / 100.0
        let horizon = min(max(settings.horizonPercent / 100.0, 0.01), 0.99)
        let rotation = settings.rotationDegrees * .pi / 180.0
        let background: (Double, Double, Double, Double) = switch settings.background {
        case .transparent: (0, 0, 0, 0)
        case .black: (0, 0, 0, 255)
        case .white: (255, 255, 255, 255)
        }

        for y in 0..<side {
            if Task.isCancelled { throw CancellationError() }
            for x in 0..<side {
                let dx = (Double(x) + 0.5 - center) / radius
                let dy = (Double(y) + 0.5 - center) / radius
                let normalizedRadius = hypot(dx, dy)
                let destinationOffset = (y * side + x) * 4
                guard normalizedRadius <= 1.0 else {
                    write(background, to: &output, at: destinationOffset)
                    continue
                }

                // In a stereographic little-planet projection the nadir is at
                // the center, the horizon is a ring inside the image, and the
                // sky continues outward from that ring. `horizon` specifies
                // the ring's relative radius within the circular crop.
                let stereographicRadius = normalizedRadius / horizon
                let latitude = 2.0 * atan(stereographicRadius) - .pi / 2.0
                let longitude = atan2(dx, -dy) + rotation
                let wrappedLongitude = longitude - floor(longitude / (2.0 * .pi))
                    * 2.0 * .pi
                let sourceX = wrappedLongitude / (2.0 * .pi)
                    * Double(source.width)
                let sourceY = min(
                    max(0.5 + latitude / .pi, 0.0), 1.0
                ) * Double(source.height - 1)
                let sampled = sample(source, x: sourceX, y: sourceY)
                let edgeCoverage = min(max((1.0 - normalizedRadius) * radius + 0.5, 0), 1)
                let pixel: (Double, Double, Double, Double)
                if settings.background == .transparent {
                    pixel = (
                        sampled.0 * edgeCoverage,
                        sampled.1 * edgeCoverage,
                        sampled.2 * edgeCoverage,
                        sampled.3 * edgeCoverage
                    )
                } else {
                    pixel = (
                        sampled.0 * edgeCoverage + background.0 * (1 - edgeCoverage),
                        sampled.1 * edgeCoverage + background.1 * (1 - edgeCoverage),
                        sampled.2 * edgeCoverage + background.2 * (1 - edgeCoverage),
                        255
                    )
                }
                write(pixel, to: &output, at: destinationOffset)
            }
        }

        let data = Data(output)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: side * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func sample(
        _ source: LittlePlanetSource,
        x: Double,
        y: Double
    ) -> (Double, Double, Double, Double) {
        let x0 = Int(floor(x)) % source.width
        let x1 = (x0 + 1) % source.width
        let y0 = min(max(Int(floor(y)), 0), source.height - 1)
        let y1 = min(y0 + 1, source.height - 1)
        let tx = x - floor(x)
        let ty = y - floor(y)

        func component(_ x: Int, _ y: Int, _ channel: Int) -> Double {
            Double(source.pixels[(y * source.width + x) * 4 + channel])
        }
        func interpolated(_ channel: Int) -> Double {
            let top = component(x0, y0, channel) * (1 - tx)
                + component(x1, y0, channel) * tx
            let bottom = component(x0, y1, channel) * (1 - tx)
                + component(x1, y1, channel) * tx
            return top * (1 - ty) + bottom * ty
        }
        return (
            interpolated(0), interpolated(1),
            interpolated(2), interpolated(3)
        )
    }

    private static func write(
        _ pixel: (Double, Double, Double, Double),
        to output: inout [UInt8],
        at offset: Int
    ) {
        output[offset] = UInt8(clamping: Int(pixel.0.rounded()))
        output[offset + 1] = UInt8(clamping: Int(pixel.1.rounded()))
        output[offset + 2] = UInt8(clamping: Int(pixel.2.rounded()))
        output[offset + 3] = UInt8(clamping: Int(pixel.3.rounded()))
    }
}
