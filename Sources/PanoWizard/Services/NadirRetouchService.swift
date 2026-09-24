import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PanoramaPole: String, Codable, CaseIterable, Sendable {
    case zenith
    case nadir

    var pitchDegrees: Double { self == .zenith ? 90 : -90 }
    var displayName: String { self == .zenith ? "Zenith" : "Nadir" }
    var localizedName: String { displayName.lowercased() }
}

enum PoleRetouchError: LocalizedError {
    case unreadableImage
    case emptyMask
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
            "The image could not be read."
        case .emptyMask:
            "Paint the area to retouch."
        case let .invalidDimensions(pole, expected, width, height):
            "The \(pole.displayName.lowercased()) plate must be \(expected) × \(expected) px, but the image is \(width) × \(height) px."
        case .writeFailed:
            "The pole plate could not be saved."
        }
    }
}

struct PoleRetouchService: Sendable {
    static let plateSize = 2_048
    static let fieldOfViewDegrees = 90.0
    private static let repairProjectionScale = 0.288_675_134_6
    private static let retouchProjectionScale = 0.5
    private static let edgeFeatherFraction = 0.06
    private static let aiPatchFeatherFraction = 0.01
    private static let radiometricBandOuterFeatherMultiple = 4.0
    private static let radiometricClipMargin = 8.0 / 255.0

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

    func prepareAIRetouchInput(
        from sourceURL: URL,
        maskData: Data,
        pole: PanoramaPole,
        expectedSize: Int = Self.plateSize
    ) throws -> Data {
        var image = try RGBAImage(contentsOf: sourceURL)
        let mask = try RGBAImage(data: maskData)
        guard image.width == expectedSize, image.height == expectedSize else {
            throw PoleRetouchError.invalidDimensions(
                pole: pole,
                expected: expectedSize,
                width: image.width,
                height: image.height
            )
        }
        guard mask.width == expectedSize, mask.height == expectedSize else {
            throw PoleRetouchError.invalidDimensions(
                pole: pole,
                expected: expectedSize,
                width: mask.width,
                height: mask.height
            )
        }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let retained = 1 - mask.pixel(x: x, y: y).a
                var pixel = image.pixel(x: x, y: y)
                pixel.r *= retained
                pixel.g *= retained
                pixel.b *= retained
                pixel.a *= retained
                image.setPixel(pixel, x: x, y: y)
            }
        }
        return try image.pngData()
    }

    func prepareAIRetouchMask(
        from sourceURL: URL,
        existingMaskData: Data?,
        pole: PanoramaPole,
        expectedSize: Int = Self.plateSize
    ) throws -> Data? {
        let source = try RGBAImage(contentsOf: sourceURL)
        guard source.width == expectedSize, source.height == expectedSize else {
            throw PoleRetouchError.invalidDimensions(
                pole: pole,
                expected: expectedSize,
                width: source.width,
                height: source.height
            )
        }
        var mask: RGBAImage
        if let existingMaskData {
            mask = try RGBAImage(data: existingMaskData)
            guard mask.width == expectedSize, mask.height == expectedSize else {
                throw PoleRetouchError.invalidDimensions(
                    pole: pole,
                    expected: expectedSize,
                    width: mask.width,
                    height: mask.height
                )
            }
        } else {
            mask = RGBAImage(width: expectedSize, height: expectedSize)
        }

        var foundTransparency = false
        for y in 0..<source.height {
            for x in 0..<source.width {
                guard source.pixel(x: x, y: y).a == 0 else {
                    continue
                }
                foundTransparency = true
                mask.setPixel(
                    Pixel(r: 1, g: 0.12, b: 0.08, a: 1),
                    x: x,
                    y: y
                )
            }
        }
        return foundTransparency ? try mask.pngData() : existingMaskData
    }

    func prepareAIRetouchPatch(
        originalURL: URL,
        editedURL: URL,
        maskData: Data,
        pole: PanoramaPole,
        overlayURL: URL,
        previewURL: URL,
        expectedSize: Int = Self.plateSize
    ) throws {
        let original = try RGBAImage(contentsOf: originalURL)
        let edited = try RGBAImage(contentsOf: editedURL)
        let mask = try RGBAImage(data: maskData)
        for image in [original, edited, mask]
        where image.width != expectedSize || image.height != expectedSize {
            throw PoleRetouchError.invalidDimensions(
                pole: pole,
                expected: expectedSize,
                width: image.width,
                height: image.height
            )
        }

        let width = original.width
        let height = original.height
        var painted = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                painted[y * width + x] = mask.pixel(x: x, y: y).a > 0
            }
        }
        guard painted.contains(true) else { throw PoleRetouchError.emptyMask }

        let distance = Self.euclideanDistanceToPaintedArea(
            painted,
            width: width,
            height: height
        )
        let featherWidth = max(
            1,
            Double(min(width, height)) * Self.aiPatchFeatherFraction
        )
        let offset = Self.radiometricOffset(
            original: original,
            edited: edited,
            painted: painted,
            distance: distance,
            featherWidth: featherWidth
        )

        var overlay = RGBAImage(width: width, height: height)
        var preview = original
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let alpha: Double
                if painted[index] {
                    alpha = 1
                } else if distance[index] < featherWidth {
                    let t = 1 - distance[index] / featherWidth
                    alpha = t * t * (3 - 2 * t)
                } else {
                    alpha = 0
                }
                guard alpha > 0 else { continue }

                let source = edited.pixel(x: x, y: y)
                let corrected = Pixel(
                    r: min(max(source.r + offset.r, 0), 1),
                    g: min(max(source.g + offset.g, 0), 1),
                    b: min(max(source.b + offset.b, 0), 1),
                    a: 1
                )
                let patch = Pixel(
                    r: corrected.r * alpha,
                    g: corrected.g * alpha,
                    b: corrected.b * alpha,
                    a: alpha
                )
                // The existing compositor expects premultiplied RGB and exact
                // zeroes wherever the overlay is transparent.
                overlay.setPixel(patch, x: x, y: y)
                preview.setPixel(
                    Self.blend(patch, over: original.pixel(x: x, y: y)),
                    x: x,
                    y: y
                )
            }
        }
        try overlay.writePNG(to: overlayURL)
        try preview.writePNG(to: previewURL)
    }

    func flattenRetouches(
        panoramaURL: URL,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        to destinationURL: URL
    ) throws {
        try flattenPanorama(
            panoramaURL: panoramaURL,
            nadirOverlayURL: nil,
            zenithOverlayURL: nil,
            nadirRetouchURL: nadirRetouchURL,
            zenithRetouchURL: zenithRetouchURL,
            to: destinationURL
        )
    }

    func flattenPanorama(
        panoramaURL: URL,
        nadirOverlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        to destinationURL: URL
    ) throws {
        var panorama = try RGBAImage(contentsOf: panoramaURL)
        let overlays: [(PanoramaPole, RGBAImage)] = try [
            nadirOverlayURL.map { (.nadir, try RGBAImage(contentsOf: $0)) },
            zenithOverlayURL.map { (.zenith, try RGBAImage(contentsOf: $0)) }
        ].compactMap { $0 }
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
                for (pole, overlay) in overlays {
                    let poleAxis = pole == .nadir ? -directionY : directionY
                    guard poleAxis > 0.000_1 else { continue }
                    let localX = directionX / poleAxis
                    let localY = (pole == .nadir ? -directionZ : directionZ)
                        / poleAxis
                    let overlayX = 0.5 + Self.repairProjectionScale * localX
                    let overlayY = 0.5 + Self.repairProjectionScale * localY
                    guard (0...1).contains(overlayX),
                          (0...1).contains(overlayY) else { continue }
                    pixel = Self.blend(
                        overlay.sample(x: overlayX, y: overlayY),
                        over: pixel
                    )
                }
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

    private static func radiometricOffset(
        original: RGBAImage,
        edited: RGBAImage,
        painted: [Bool],
        distance: [Double],
        featherWidth: Double
    ) -> Pixel {
        var red = [Double]()
        var green = [Double]()
        var blue = [Double]()
        let outerDistance = featherWidth * radiometricBandOuterFeatherMultiple
        for y in 0..<original.height {
            for x in 0..<original.width {
                let index = y * original.width + x
                guard !painted[index],
                      distance[index] >= featherWidth,
                      distance[index] < outerDistance else { continue }
                let before = original.pixel(x: x, y: y)
                let after = edited.pixel(x: x, y: y)
                if isRadiometricallyValid(before.r),
                   isRadiometricallyValid(after.r) {
                    red.append(before.r - after.r)
                }
                if isRadiometricallyValid(before.g),
                   isRadiometricallyValid(after.g) {
                    green.append(before.g - after.g)
                }
                if isRadiometricallyValid(before.b),
                   isRadiometricallyValid(after.b) {
                    blue.append(before.b - after.b)
                }
            }
        }
        return Pixel(
            r: median(red),
            g: median(green),
            b: median(blue),
            a: 1
        )
    }

    private static func isRadiometricallyValid(_ value: Double) -> Bool {
        value > radiometricClipMargin && value < 1 - radiometricClipMargin
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func euclideanDistanceToPaintedArea(
        _ painted: [Bool],
        width: Int,
        height: Int
    ) -> [Double] {
        let maximumSquaredDistance = Double(width * width + height * height + 1)
        var horizontal = [Double](
            repeating: maximumSquaredDistance,
            count: width * height
        )
        var input = [Double](repeating: 0, count: max(width, height))
        var output = input

        for y in 0..<height {
            for x in 0..<width {
                input[x] = painted[y * width + x] ? 0 : maximumSquaredDistance
            }
            squaredDistanceTransform(input, count: width, output: &output)
            for x in 0..<width { horizontal[y * width + x] = output[x] }
        }

        var result = [Double](repeating: 0, count: width * height)
        for x in 0..<width {
            for y in 0..<height { input[y] = horizontal[y * width + x] }
            squaredDistanceTransform(input, count: height, output: &output)
            for y in 0..<height { result[y * width + x] = sqrt(output[y]) }
        }
        return result
    }

    private static func squaredDistanceTransform(
        _ input: [Double],
        count: Int,
        output: inout [Double]
    ) {
        guard count > 0 else { return }
        var locations = [Int](repeating: 0, count: count)
        var boundaries = [Double](repeating: 0, count: count + 1)
        var envelopeIndex = 0
        locations[0] = 0
        boundaries[0] = -.infinity
        boundaries[1] = .infinity

        if count > 1 {
            for point in 1..<count {
                var intersection: Double
                repeat {
                    let location = locations[envelopeIndex]
                    intersection = (
                        input[point] + Double(point * point)
                            - input[location] - Double(location * location)
                    ) / Double(2 * (point - location))
                    if intersection <= boundaries[envelopeIndex] {
                        envelopeIndex -= 1
                    } else {
                        break
                    }
                } while envelopeIndex >= 0
                envelopeIndex += 1
                locations[envelopeIndex] = point
                boundaries[envelopeIndex] = intersection
                boundaries[envelopeIndex + 1] = .infinity
            }
        }

        envelopeIndex = 0
        for point in 0..<count {
            while boundaries[envelopeIndex + 1] < Double(point) {
                envelopeIndex += 1
            }
            let delta = point - locations[envelopeIndex]
            output[point] = Double(delta * delta) + input[locations[envelopeIndex]]
        }
    }

}

struct Pixel {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
}

struct RGBAImage {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytes = Array(repeating: 0, count: width * height * 4)
    }

    init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { throw PoleRetouchError.unreadableImage }
        try self.init(source: source)
    }

    init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { throw PoleRetouchError.unreadableImage }
        try self.init(source: source)
    }

    private init(source: CGImageSource) throws {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
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

    func pngData() throws -> Data {
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
        let data = NSMutableData()
        guard let image,
              let destination = CGImageDestinationCreateWithData(
                data,
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
        return data as Data
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
