import Foundation

enum PanoramaAdjustmentProcessor {
    static func writeRenderedPanorama(
        panoramaURL: URL,
        nadirOverlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        adjustments: PanoramaAdjustments,
        to destinationURL: URL
    ) throws {
        let hasLayers = nadirOverlayURL != nil || zenithOverlayURL != nil
            || nadirRetouchURL != nil || zenithRetouchURL != nil
        let compositeURL = FileManager.default.temporaryDirectory.appending(
            path: "\(UUID().uuidString)-panorama-composite.png"
        )
        if hasLayers {
            try PoleRetouchService().flattenPanorama(
                panoramaURL: panoramaURL,
                nadirOverlayURL: nadirOverlayURL,
                zenithOverlayURL: zenithOverlayURL,
                nadirRetouchURL: nadirRetouchURL,
                zenithRetouchURL: zenithRetouchURL,
                to: compositeURL
            )
        }
        defer {
            if hasLayers { try? FileManager.default.removeItem(at: compositeURL) }
        }
        try writeAdjustedImage(
            from: hasLayers ? compositeURL : panoramaURL,
            adjustments: adjustments,
            to: destinationURL
        )
    }

    static func writeAdjustedImage(
        from sourceURL: URL,
        adjustments: PanoramaAdjustments,
        to destinationURL: URL
    ) throws {
        var image = try RGBAImage(contentsOf: sourceURL)
        let settings = adjustments.sanitized
        for y in 0..<image.height {
            if Task.isCancelled { throw CancellationError() }
            for x in 0..<image.width {
                image.setPixel(
                    adjusted(
                        image.pixel(x: x, y: y),
                        settings: settings
                    ),
                    x: x,
                    y: y
                )
            }
        }
        try image.writePNG(to: destinationURL)
    }

    static func adjusted(
        _ pixel: Pixel,
        settings: PanoramaAdjustments
    ) -> Pixel {
        let settings = settings.sanitized
        var red = srgbToLinear(clamp(pixel.r))
        var green = srgbToLinear(clamp(pixel.g))
        var blue = srgbToLinear(clamp(pixel.b))

        let exposureFactor = pow(2, settings.exposure)
        red *= exposureFactor
        green *= exposureFactor
        blue *= exposureFactor

        let brightness = settings.brightness / 100 * 0.25
        red += brightness
        green += brightness
        blue += brightness

        var luminance = luma(red, green, blue)
        let shadowMask = pow(clamp(1 - luminance), 2)
        let highlightMask = pow(clamp(luminance), 2)
        let shadowOffset = settings.shadows / 100 * shadowMask * 0.35
        let highlightOffset = settings.highlights / 100 * highlightMask * 0.35
        red += shadowOffset + highlightOffset
        green += shadowOffset + highlightOffset
        blue += shadowOffset + highlightOffset

        let whiteMask = smoothstep(0.55, 1, luminance)
        let blackMask = 1 - smoothstep(0, 0.45, luminance)
        let whiteFactor = 1 + settings.whites / 100 * whiteMask * 0.35
        let blackOffset = settings.blacks / 100 * blackMask * 0.20
        red = red * whiteFactor + blackOffset
        green = green * whiteFactor + blackOffset
        blue = blue * whiteFactor + blackOffset

        let contrastFactor = pow(2, settings.contrast / 100)
        red = clamp((red - 0.18) * contrastFactor + 0.18)
        green = clamp((green - 0.18) * contrastFactor + 0.18)
        blue = clamp((blue - 0.18) * contrastFactor + 0.18)

        let temperature = settings.temperature / 100
        let tint = settings.tint / 100
        red += temperature * (1 - red) * 0.12
        blue -= temperature * (1 - blue) * 0.12
        red += tint * (1 - red) * 0.04
        green -= tint * (1 - green) * 0.08
        blue += tint * (1 - blue) * 0.04

        luminance = luma(red, green, blue)
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        let chroma = maximum - minimum
        let vibranceFactor = 1 + settings.vibrance / 100 * (1 - clamp(chroma))
        red = mix(luminance, red, vibranceFactor)
        green = mix(luminance, green, vibranceFactor)
        blue = mix(luminance, blue, vibranceFactor)

        luminance = luma(red, green, blue)
        let saturationFactor = 1 + settings.saturation / 100
        red = mix(luminance, red, saturationFactor)
        green = mix(luminance, green, saturationFactor)
        blue = mix(luminance, blue, saturationFactor)

        return Pixel(
            r: linearToSRGB(clamp(red)),
            g: linearToSRGB(clamp(green)),
            b: linearToSRGB(clamp(blue)),
            a: pixel.a
        )
    }

    private static func luma(_ red: Double, _ green: Double, _ blue: Double)
        -> Double {
        red * 0.2126 + green * 0.7152 + blue * 0.0722
    }

    private static func mix(_ first: Double, _ second: Double, _ amount: Double)
        -> Double {
        first * (1 - amount) + second * amount
    }

    private static func smoothstep(
        _ lower: Double,
        _ upper: Double,
        _ value: Double
    ) -> Double {
        let normalized = clamp((value - lower) / (upper - lower))
        return normalized * normalized * (3 - 2 * normalized)
    }

    private static func srgbToLinear(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Double) -> Double {
        value <= 0.003_130_8
            ? value * 12.92
            : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
