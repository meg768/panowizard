import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct LittlePlanetSettings: Equatable, Sendable {
    var rotationDegrees = 0.0
    var horizonPercent = 50.0
    var centerLongitudeDegrees = 0.0
    var centerLatitudeDegrees = -90.0
}

struct LittlePlanetProjection: Sendable {
    private let center: Double
    private let radius: Double
    private let horizon: Double
    private let rotation: Double
    private let usesDefaultCenter: Bool
    private let centerLongitudeSin: Double
    private let centerLongitudeCos: Double
    private let centerTiltSin: Double
    private let centerTiltCos: Double

    init(side: Int, settings: LittlePlanetSettings) {
        center = Double(side) / 2.0
        radius = max(Double(side) / 2.0 - 2.0, 1.0)
        horizon = min(max(settings.horizonPercent / 100.0, 0.01), 0.99)
        rotation = settings.rotationDegrees * .pi / 180.0
        usesDefaultCenter = settings.centerLongitudeDegrees == 0.0
            && settings.centerLatitudeDegrees == -90.0

        let centerLongitude = settings.centerLongitudeDegrees * .pi / 180.0
        let centerLatitude = min(
            max(settings.centerLatitudeDegrees, -90.0),
            90.0
        ) * .pi / 180.0
        let centerTilt = -(centerLatitude + .pi / 2.0)
        centerLongitudeSin = sin(centerLongitude)
        centerLongitudeCos = cos(centerLongitude)
        centerTiltSin = sin(centerTilt)
        centerTiltCos = cos(centerTilt)
    }

    func sourceDirection(
        outputX: Double,
        outputY: Double
    ) -> (longitude: Double, latitude: Double) {
        let dx = (outputX - center) / radius
        let dy = (outputY - center) / radius
        let normalizedRadius = hypot(dx, dy)
        let stereographicRadius = normalizedRadius / horizon
        let latitude = 2.0 * atan(stereographicRadius) - .pi / 2.0
        let longitude = atan2(dx, -dy) + rotation

        // Keep the established path exact for the default center.
        guard !usesDefaultCenter else { return (longitude, latitude) }

        let latitudeCos = cos(latitude)
        let localX = latitudeCos * cos(longitude)
        let localY = latitudeCos * sin(longitude)
        let localZ = sin(latitude)

        let tiltedX = centerTiltCos * localX + centerTiltSin * localZ
        let tiltedZ = -centerTiltSin * localX + centerTiltCos * localZ
        let worldX = centerLongitudeCos * tiltedX
            - centerLongitudeSin * localY
        let worldY = centerLongitudeSin * tiltedX
            + centerLongitudeCos * localY

        return (
            atan2(worldY, worldX),
            asin(min(max(tiltedZ, -1.0), 1.0))
        )
    }
}

struct LittlePlanetSource: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(
        panoramaURL: URL,
        adjustments: PanoramaAdjustments
    ) throws {
        let needsRendering = !adjustments.isNeutral
        guard needsRendering else {
            try self.init(url: panoramaURL)
            return
        }
        let flattenedURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-little-planet-panorama.png"
        )
        defer { try? FileManager.default.removeItem(at: flattenedURL) }
        try PanoramaAdjustmentProcessor.writeRenderedPanorama(
            panoramaURL: panoramaURL,
            adjustments: adjustments,
            to: flattenedURL
        )
        try self.init(url: flattenedURL)
    }

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

    func makeImage() throws -> CGImage {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
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
        else { throw CocoaError(.fileReadCorruptFile) }
        return image
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
        let projection = LittlePlanetProjection(side: side, settings: settings)

        for y in 0..<side {
            if Task.isCancelled { throw CancellationError() }
            for x in 0..<side {
                let destinationOffset = ((side - 1 - y) * side + x) * 4
                let direction = projection.sourceDirection(
                    outputX: Double(x) + 0.5,
                    outputY: Double(y) + 0.5
                )
                let wrappedLongitude = direction.longitude
                    - floor(direction.longitude / (2.0 * .pi))
                    * 2.0 * .pi
                let sourceX = wrappedLongitude / (2.0 * .pi)
                    * Double(source.width)
                let sourceY = min(
                    max(0.5 + direction.latitude / .pi, 0.0), 1.0
                ) * Double(source.height - 1)
                let sampled = sample(source, x: sourceX, y: sourceY)
                write(sampled, to: &output, at: destinationOffset)
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
