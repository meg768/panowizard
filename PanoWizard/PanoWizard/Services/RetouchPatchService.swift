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
    private static let aiPatchFeatherWidth = 128

    func maskForTransparentPixels(
        in sourceURL: URL,
        expectedSize: Int = Self.patchSize
    ) throws -> Data? {
        let source = try RGBAImage(contentsOf: sourceURL)
        guard source.width == expectedSize, source.height == expectedSize else {
            throw RetouchPatchError.invalidDimensions(
                expected: expectedSize,
                width: source.width,
                height: source.height
            )
        }

        var mask = RGBAImage(width: source.width, height: source.height)
        var containsTransparentPixels = false
        let maskPixel = Pixel(r: 1, g: 0.12, b: 0.08, a: 1)
        for y in 0..<source.height {
            if Task.isCancelled { throw CancellationError() }
            for x in 0..<source.width where source.pixel(x: x, y: y).a < 1 {
                mask.setPixel(maskPixel, x: x, y: y)
                containsTransparentPixels = true
            }
        }
        return containsTransparentPixels ? try mask.pngData() : nil
    }

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

    func prepareAIRetouchAPIInputMask(
        from maskData: Data,
        sourceURL: URL,
        expectedSize: Int = Self.patchSize
    ) throws -> Data {
        let source = try RGBAImage(contentsOf: sourceURL)
        let userMask = try RGBAImage(data: maskData)
        for image in [source, userMask]
        where image.width != expectedSize || image.height != expectedSize {
            throw RetouchPatchError.invalidDimensions(
                expected: expectedSize,
                width: image.width,
                height: image.height
            )
        }

        var apiMask = RGBAImage(width: userMask.width, height: userMask.height)
        var containsPaintedPixels = false
        for y in 0..<userMask.height {
            for x in 0..<userMask.width {
                let isPainted = userMask.pixel(x: x, y: y).a > 0
                containsPaintedPixels = containsPaintedPixels || isPainted
                apiMask.setPixel(
                    Pixel(r: 1, g: 1, b: 1, a: isPainted ? 0 : 1),
                    x: x,
                    y: y
                )
            }
        }
        guard containsPaintedPixels else { throw RetouchPatchError.emptyMask }
        return try apiMask.pngData()
    }

    func prepareAIRetouchPatch(
        originalURL: URL,
        editedURL: URL,
        maskData _: Data,
        overlayURL: URL,
        previewURL: URL,
        expectedSize: Int = Self.patchSize
    ) throws {
        var edited = try RGBAImage(contentsOf: editedURL)
        guard edited.width == expectedSize, edited.height == expectedSize else {
            throw RetouchPatchError.invalidDimensions(
                expected: expectedSize,
                width: edited.width,
                height: edited.height
            )
        }
        for y in 0..<edited.height {
            let verticalOpacity = Self.edgeOpacity(
                distance: min(y, edited.height - 1 - y)
            )
            for x in 0..<edited.width {
                let horizontalOpacity = Self.edgeOpacity(
                    distance: min(x, edited.width - 1 - x)
                )
                let opacity = horizontalOpacity * verticalOpacity
                var pixel = edited.pixel(x: x, y: y)
                pixel.r *= opacity
                pixel.g *= opacity
                pixel.b *= opacity
                pixel.a *= opacity
                edited.setPixel(pixel, x: x, y: y)
            }
        }
        try edited.writePNG(to: overlayURL)
        try compositePatch(
            backgroundURL: originalURL,
            patchURL: overlayURL,
            to: previewURL,
            expectedSize: expectedSize
        )
    }

    private static func edgeOpacity(distance: Int) -> Double {
        let progress = min(Double(distance) / Double(aiPatchFeatherWidth), 1)
        return progress * progress * (3 - 2 * progress)
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
