import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PanoramaPole: String, Codable, CaseIterable, Sendable {
    case zenith
    case nadir

    var pitchDegrees: Double { self == .zenith ? 90 : -90 }
    var displayName: String { self == .zenith ? "Zenit" : "Nadir" }
}

enum PoleRetouchError: LocalizedError {
    case unreadableImage
    case invalidDimensions(
        pole: PanoramaPole,
        expected: Int,
        width: Int,
        height: Int
    )
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "Bilden kunde inte läsas."
        case let .invalidDimensions(pole, expected, width, height):
            "\(pole.displayName)plattan måste vara \(expected) × \(expected) px, men bilden är \(width) × \(height) px."
        case .writeFailed:
            "Nadirplattan kunde inte sparas."
        }
    }
}

struct PoleRetouchService: Sendable {
    static let plateSize = 2_048
    static let fieldOfViewDegrees = 90.0
    private static let repairProjectionScale = 0.288_675_134_6
    private static let retouchProjectionScale = 0.5
    private static let edgeFeatherFraction = 0.06

    func exportPlate(
        panoramaURL: URL,
        repairOverlayURL: URL?,
        existingRetouchURL: URL?,
        pole: PanoramaPole,
        to destinationURL: URL,
        size: Int = Self.plateSize
    ) throws {
        let panorama = try RGBAImage(contentsOf: panoramaURL)
        let repairOverlay = try repairOverlayURL.map(RGBAImage.init(contentsOf:))
        let existingRetouch = try existingRetouchURL.map(RGBAImage.init(contentsOf:))
        var result = RGBAImage(width: size, height: size)

        for y in 0..<size {
            let localY = 2 * ((Double(y) + 0.5) / Double(size)) - 1
            for x in 0..<size {
                let localX = 2 * ((Double(x) + 0.5) / Double(size)) - 1
                let directionLength = sqrt(localX * localX + localY * localY + 1)
                let directionX = localX / directionLength
                let directionY = (pole == .nadir ? -1 : 1) / directionLength
                let directionZ = (pole == .nadir ? -localY : localY)
                    / directionLength
                let longitude = atan2(directionX, directionZ)
                let latitude = asin(directionY)
                let panoramaX = 0.5 + longitude / (2 * .pi)
                let panoramaY = 0.5 - latitude / .pi
                var pixel = panorama.sample(
                    x: panoramaX,
                    y: panoramaY,
                    wrappingX: true
                )

                if let repairOverlay {
                    let repairX = 0.5 + Self.repairProjectionScale * localX
                    let repairY = 0.5 + Self.repairProjectionScale * localY
                    if (0...1).contains(repairX), (0...1).contains(repairY) {
                        pixel = Self.blend(
                            repairOverlay.sample(x: repairX, y: repairY),
                            over: pixel
                        )
                    }
                }
                if let existingRetouch {
                    pixel = Self.blend(
                        existingRetouch.sample(
                            x: (Double(x) + 0.5) / Double(size),
                            y: (Double(y) + 0.5) / Double(size)
                        ),
                        over: pixel
                    )
                }
                pixel.a = 1
                result.setPixel(pixel, x: x, y: y)
            }
        }
        try result.writePNG(to: destinationURL)
    }

    func prepareImportedPlate(
        from sourceURL: URL,
        pole: PanoramaPole,
        to destinationURL: URL,
        expectedSize: Int = Self.plateSize
    ) throws {
        var image = try RGBAImage(contentsOf: sourceURL)
        guard image.width == expectedSize, image.height == expectedSize else {
            throw PoleRetouchError.invalidDimensions(
                pole: pole,
                expected: expectedSize,
                width: image.width,
                height: image.height
            )
        }
        let featherWidth = Double(expectedSize) * Self.edgeFeatherFraction
        for y in 0..<image.height {
            for x in 0..<image.width {
                let distance = Double(min(x, y, image.width - 1 - x, image.height - 1 - y))
                let t = min(max(distance / featherWidth, 0), 1)
                let feather = t * t * (3 - 2 * t)
                var pixel = image.pixel(x: x, y: y)
                pixel.r *= feather
                pixel.g *= feather
                pixel.b *= feather
                pixel.a *= feather
                image.setPixel(pixel, x: x, y: y)
            }
        }
        try image.writePNG(to: destinationURL)
    }

    func flattenRetouches(
        panoramaURL: URL,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        to destinationURL: URL
    ) throws {
        var panorama = try RGBAImage(contentsOf: panoramaURL)
        let retouches: [(PanoramaPole, RGBAImage)] = try [
            nadirRetouchURL.map { (.nadir, try RGBAImage(contentsOf: $0)) },
            zenithRetouchURL.map { (.zenith, try RGBAImage(contentsOf: $0)) }
        ].compactMap { $0 }
        for y in 0..<panorama.height {
            let latitude = (0.5 - (Double(y) + 0.5) / Double(panorama.height)) * .pi
            let directionY = sin(latitude)
            let horizontalRadius = cos(latitude)
            for x in 0..<panorama.width {
                let longitude = ((Double(x) + 0.5) / Double(panorama.width) - 0.5) * 2 * .pi
                let directionX = sin(longitude) * horizontalRadius
                let directionZ = cos(longitude) * horizontalRadius
                var pixel = panorama.pixel(x: x, y: y)
                for (pole, retouch) in retouches {
                    let poleAxis = pole == .nadir ? -directionY : directionY
                    guard poleAxis > 0.000_1 else { continue }
                    let localX = directionX / poleAxis
                    let localY = (pole == .nadir ? -directionZ : directionZ)
                        / poleAxis
                    let retouchX = 0.5 + Self.retouchProjectionScale * localX
                    let retouchY = 0.5 + Self.retouchProjectionScale * localY
                    guard (0...1).contains(retouchX),
                          (0...1).contains(retouchY) else { continue }
                    let overlay = retouch.sample(x: retouchX, y: retouchY)
                    pixel = Self.blend(overlay, over: pixel)
                }
                panorama.setPixel(pixel, x: x, y: y)
            }
        }
        try panorama.writePNG(to: destinationURL)
    }

    private static func blend(_ foreground: Pixel, over background: Pixel) -> Pixel {
        let inverseAlpha = 1 - foreground.a
        return Pixel(
            r: foreground.r + background.r * inverseAlpha,
            g: foreground.g + background.g * inverseAlpha,
            b: foreground.b + background.b * inverseAlpha,
            a: foreground.a + background.a * inverseAlpha
        )
    }

}

private struct Pixel {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
}

private struct RGBAImage {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytes = Array(repeating: 0, count: width * height * 4)
    }

    init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw PoleRetouchError.unreadableImage }
        width = image.width
        height = image.height
        bytes = Array(repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer in
            guard let data = buffer.baseAddress,
                  let context = Self.context(
                      data: data,
                      width: width,
                      height: height
                  ) else { return false }
            context.interpolationQuality = .high
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else { throw PoleRetouchError.unreadableImage }
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let index = (y * width + x) * 4
        return Pixel(
            r: Double(bytes[index]) / 255,
            g: Double(bytes[index + 1]) / 255,
            b: Double(bytes[index + 2]) / 255,
            a: Double(bytes[index + 3]) / 255
        )
    }

    mutating func setPixel(_ pixel: Pixel, x: Int, y: Int) {
        let index = (y * width + x) * 4
        bytes[index] = UInt8(clamping: Int((pixel.r * 255).rounded()))
        bytes[index + 1] = UInt8(clamping: Int((pixel.g * 255).rounded()))
        bytes[index + 2] = UInt8(clamping: Int((pixel.b * 255).rounded()))
        bytes[index + 3] = UInt8(clamping: Int((pixel.a * 255).rounded()))
    }

    func sample(x: Double, y: Double, wrappingX: Bool = false) -> Pixel {
        let resolvedX = wrappingX ? x - floor(x) : min(max(x, 0), 1)
        let resolvedY = min(max(y, 0), 1)
        let imageX = resolvedX * Double(width) - 0.5
        let imageY = resolvedY * Double(height) - 0.5
        let x0 = Int(floor(imageX))
        let y0 = Int(floor(imageY))
        let fx = imageX - Double(x0)
        let fy = imageY - Double(y0)

        func resolvedPixel(_ x: Int, _ y: Int) -> Pixel {
            let px: Int
            if wrappingX {
                px = (x % width + width) % width
            } else {
                px = min(max(x, 0), width - 1)
            }
            return pixel(x: px, y: min(max(y, 0), height - 1))
        }

        let topLeft = resolvedPixel(x0, y0)
        let topRight = resolvedPixel(x0 + 1, y0)
        let bottomLeft = resolvedPixel(x0, y0 + 1)
        let bottomRight = resolvedPixel(x0 + 1, y0 + 1)
        func interpolate(_ keyPath: KeyPath<Pixel, Double>) -> Double {
            let top = topLeft[keyPath: keyPath] * (1 - fx)
                + topRight[keyPath: keyPath] * fx
            let bottom = bottomLeft[keyPath: keyPath] * (1 - fx)
                + bottomRight[keyPath: keyPath] * fx
            return top * (1 - fy) + bottom * fy
        }
        return Pixel(
            r: interpolate(\.r),
            g: interpolate(\.g),
            b: interpolate(\.b),
            a: interpolate(\.a)
        )
    }

    func writePNG(to url: URL) throws {
        var copy = bytes
        let image = copy.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let data = buffer.baseAddress,
                  let context = Self.context(
                      data: data,
                      width: width,
                      height: height
                  ) else { return nil }
            return context.makeImage()
        }
        guard let image,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else { throw PoleRetouchError.writeFailed }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PoleRetouchError.writeFailed
        }
    }

    private static func context(
        data: UnsafeMutableRawPointer,
        width: Int,
        height: Int
    ) -> CGContext? {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }
}
