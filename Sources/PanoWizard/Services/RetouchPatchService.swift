import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RetouchPatchError: LocalizedError {
    case unreadableImage
    case emptyMask
    case invalidDimensions(expected: Int, width: Int, height: Int)
    case patchUnavailable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "The patch image could not be read."
        case .emptyMask:
            "Paint the area to retouch."
        case let .invalidDimensions(expected, width, height):
            "The patch must be \(expected) × \(expected) px, but the image is \(width) × \(height) px."
        case .patchUnavailable:
            "The patch is no longer available."
        case .writeFailed:
            "The patch image could not be saved."
        }
    }
}

struct RetouchPatchService: Sendable {
    static let patchSize = 2_048
    private static let aiPatchFeatherFraction = 0.01
    private static let radiometricBandOuterFeatherMultiple = 4.0
    private static let radiometricClipMargin = 8.0 / 255.0

    func prepareAIRetouchInput(
        from sourceURL: URL,
        maskData: Data,
        expectedSize: Int = Self.patchSize
    ) throws -> Data {
        var image = try RGBAImage(contentsOf: sourceURL)
        let mask = try RGBAImage(data: maskData)
        guard image.width == expectedSize, image.height == expectedSize else {
            throw RetouchPatchError.invalidDimensions(
                expected: expectedSize,
                width: image.width,
                height: image.height
            )
        }
        guard mask.width == expectedSize, mask.height == expectedSize else {
            throw RetouchPatchError.invalidDimensions(
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
                pixel.a = retained
                image.setPixel(pixel, x: x, y: y)
            }
        }
        return try image.pngData()
    }

    func prepareAIRetouchPatch(
        originalURL: URL,
        editedURL: URL,
        maskData: Data,
        overlayURL: URL,
        previewURL: URL,
        expectedSize: Int = Self.patchSize
    ) throws {
        let original = try RGBAImage(contentsOf: originalURL)
        let edited = try RGBAImage(contentsOf: editedURL)
        let mask = try RGBAImage(data: maskData)
        for image in [original, edited, mask]
        where image.width != expectedSize || image.height != expectedSize {
            throw RetouchPatchError.invalidDimensions(
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
        guard painted.contains(true) else { throw RetouchPatchError.emptyMask }

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

    func exportPatch(
        panoramaURL: URL,
        viewpoint: PanoramaViewpoint,
        to destinationURL: URL,
        size: Int = Self.patchSize
    ) throws {
        let panorama = try RGBAImage(contentsOf: panoramaURL)
        var result = RGBAImage(width: size, height: size)
        let tangent = tan(viewpoint.verticalFieldOfViewDegrees * .pi / 360)
        let cosPitch = cos(viewpoint.pitchRadians)
        let sinPitch = sin(viewpoint.pitchRadians)
        let cosYaw = cos(viewpoint.yawRadians)
        let sinYaw = sin(viewpoint.yawRadians)

        for y in 0..<size {
            if Task.isCancelled { throw CancellationError() }
            let localY = 1 - 2 * ((Double(y) + 0.5) / Double(size))
            for x in 0..<size {
                let localX = 2 * ((Double(x) + 0.5) / Double(size)) - 1
                var directionX = localX * tangent
                var directionY = localY * tangent
                var directionZ = 1.0
                let length = sqrt(
                    directionX * directionX
                        + directionY * directionY
                        + directionZ * directionZ
                )
                directionX /= length
                directionY /= length
                directionZ /= length

                let pitchedY = directionY * cosPitch - directionZ * sinPitch
                let pitchedZ = directionY * sinPitch + directionZ * cosPitch
                directionY = pitchedY
                directionZ = pitchedZ
                let yawedX = directionX * cosYaw + directionZ * sinYaw
                let yawedZ = -directionX * sinYaw + directionZ * cosYaw
                directionX = yawedX
                directionZ = yawedZ

                let longitude = atan2(directionX, directionZ)
                let latitude = asin(min(max(directionY, -1), 1))
                result.setPixel(
                    panorama.sample(
                        x: 0.5 + longitude / (2 * .pi),
                        y: 0.5 - latitude / .pi,
                        wrappingX: true
                    ),
                    x: x,
                    y: y
                )
            }
        }
        try result.writePNG(to: destinationURL)
    }

    func prepareImportedPatch(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedSize: Int = Self.patchSize
    ) throws {
        let image = try RGBAImage(contentsOf: sourceURL)
        guard image.width == expectedSize, image.height == expectedSize else {
            throw RetouchPatchError.invalidDimensions(
                expected: expectedSize,
                width: image.width,
                height: image.height
            )
        }
        try image.writePNG(to: destinationURL)
    }

    func compositePatch(
        backgroundURL: URL,
        patchURL: URL,
        to destinationURL: URL,
        expectedSize: Int = Self.patchSize
    ) throws {
        var background = try RGBAImage(contentsOf: backgroundURL)
        let patch = try RGBAImage(contentsOf: patchURL)
        for image in [background, patch]
        where image.width != expectedSize || image.height != expectedSize {
            throw RetouchPatchError.invalidDimensions(
                expected: expectedSize,
                width: image.width,
                height: image.height
            )
        }
        for y in 0..<background.height {
            for x in 0..<background.width {
                background.setPixel(
                    Self.blend(
                        patch.pixel(x: x, y: y),
                        over: background.pixel(x: x, y: y)
                    ),
                    x: x,
                    y: y
                )
            }
        }
        try background.writePNG(to: destinationURL)
    }

    func render(
        panoramaURL: URL,
        patches: [(RetouchPatch, URL)],
        to destinationURL: URL,
        expectedPatchSize: Int = Self.patchSize
    ) throws {
        var panorama = try RGBAImage(contentsOf: panoramaURL)
        let active: [(PanoramaViewpoint, RGBAImage)] = try patches.compactMap {
            patch, url in
            guard patch.isEnabled else { return nil }
            let image = try RGBAImage(contentsOf: url)
            guard image.width == expectedPatchSize,
                  image.height == expectedPatchSize else {
                throw RetouchPatchError.invalidDimensions(
                    expected: expectedPatchSize,
                    width: image.width,
                    height: image.height
                )
            }
            return (patch.viewpoint, image)
        }

        for y in 0..<panorama.height {
            if Task.isCancelled { throw CancellationError() }
            let latitude = (0.5 - (Double(y) + 0.5) / Double(panorama.height)) * .pi
            let worldY = sin(latitude)
            let horizontalRadius = cos(latitude)
            for x in 0..<panorama.width {
                let longitude = (
                    (Double(x) + 0.5) / Double(panorama.width) - 0.5
                ) * 2 * .pi
                let worldX = sin(longitude) * horizontalRadius
                let worldZ = cos(longitude) * horizontalRadius
                var pixel = panorama.pixel(x: x, y: y)

                for (viewpoint, patchImage) in active {
                    let cosYaw = cos(viewpoint.yawRadians)
                    let sinYaw = sin(viewpoint.yawRadians)
                    let yawX = worldX * cosYaw - worldZ * sinYaw
                    let yawZ = worldX * sinYaw + worldZ * cosYaw
                    let cosPitch = cos(viewpoint.pitchRadians)
                    let sinPitch = sin(viewpoint.pitchRadians)
                    let localY = worldY * cosPitch + yawZ * sinPitch
                    let localZ = -worldY * sinPitch + yawZ * cosPitch
                    guard localZ > 0.000_1 else { continue }
                    let tangent = tan(
                        viewpoint.verticalFieldOfViewDegrees * .pi / 360
                    )
                    let ndcX = yawX / localZ / tangent
                    let ndcY = localY / localZ / tangent
                    guard (-1...1).contains(ndcX),
                          (-1...1).contains(ndcY) else { continue }
                    let overlay = patchImage.sample(
                        x: (ndcX + 1) / 2,
                        y: (1 - ndcY) / 2
                    )
                    let inverseAlpha = 1 - overlay.a
                    pixel = Pixel(
                        r: overlay.r + pixel.r * inverseAlpha,
                        g: overlay.g + pixel.g * inverseAlpha,
                        b: overlay.b + pixel.b * inverseAlpha,
                        a: overlay.a + pixel.a * inverseAlpha
                    )
                }
                panorama.setPixel(pixel, x: x, y: y)
            }
        }
        try panorama.writePNG(to: destinationURL)
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
        else { throw RetouchPatchError.unreadableImage }
        try self.init(source: source)
    }

    init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { throw RetouchPatchError.unreadableImage }
        try self.init(source: source)
    }

    private init(source: CGImageSource) throws {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw RetouchPatchError.unreadableImage }
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
        guard rendered else { throw RetouchPatchError.unreadableImage }
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
              ) else { throw RetouchPatchError.writeFailed }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw RetouchPatchError.writeFailed
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
              ) else { throw RetouchPatchError.writeFailed }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw RetouchPatchError.writeFailed
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
