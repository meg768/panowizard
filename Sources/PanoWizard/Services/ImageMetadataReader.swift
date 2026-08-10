import Foundation
import ImageIO

protocol ImageMetadataReading: Sendable {
    func readImage(at url: URL) async throws -> SourceImage
}

enum ImageMetadataError: LocalizedError {
    case unreadableImage(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "Kunde inte läsa \(url.lastPathComponent)."
        }
    }
}

struct ImageMetadataReader: ImageMetadataReading {
    func readImage(at url: URL) async throws -> SourceImage {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any] else {
                throw ImageMetadataError.unreadableImage(url)
            }

            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let exifAux = properties[kCGImagePropertyExifAuxDictionary]
                as? [CFString: Any]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            let lensModel = exifAux?[kCGImagePropertyExifAuxLensModel] as? String
                ?? exif?[kCGImagePropertyExifLensModel] as? String
            // Prefer the physical focal length. The 35 mm equivalent is only
            // a fallback because calibrated profiles describe the actual lens,
            // not the crop-factor-adjusted field of view.
            let focalLength = Self.doubleValue(exif?[kCGImagePropertyExifFocalLength])
                ?? Self.doubleValue(exif?[kCGImagePropertyExifFocalLenIn35mmFilm])
            let captureDate = Self.captureDate(exif: exif, tiff: tiff)
            let lensKind = Self.lensKind(
                model: lensModel,
                focalLength: focalLength,
                imageSource: source
            )

            return SourceImage(
                url: url,
                captureDate: captureDate,
                pixelWidth: width,
                pixelHeight: height,
                cameraModel: tiff?[kCGImagePropertyTIFFModel] as? String,
                lens: LensDescription(
                    model: lensModel ?? (
                        lensKind == .fisheye
                            ? "Fisheye (identifierat från bilden)"
                            : nil
                    ),
                    focalLengthIn35mm: focalLength,
                    kind: lensKind
                )
            )
        }.value
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return value as? Double
    }

    private static func captureDate(
        exif: [CFString: Any]?,
        tiff: [CFString: Any]?
    ) -> Date? {
        let value = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String

        guard let value else { return nil }
        return exifDateFormatter.date(from: value)
    }

    private static func lensKind(
        model: String?,
        focalLength: Double?,
        imageSource: CGImageSource
    ) -> LensDescription.Kind {
        if model?.localizedCaseInsensitiveContains("fisheye") == true {
            return .fisheye
        }
        if let focalLength, focalLength <= 16 {
            return .fisheye
        }
        if focalLength != nil {
            return .rectilinear
        }
        return hasFisheyeFrame(in: imageSource) ? .fisheye : .unknown
    }

    static func hasFisheyeFrame(in imageSource: CGImageSource) -> Bool {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 160
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary
        ) else {
            return false
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let patch = max(min(width, height) / 8, 2)
        let cornerOrigins = [
            (0, 0),
            (width - patch, 0),
            (0, height - patch),
            (width - patch, height - patch)
        ]
        var darkCornerPixels = 0
        var cornerPixels = 0
        for (originX, originY) in cornerOrigins {
            for y in originY..<(originY + patch) {
                for x in originX..<(originX + patch) {
                    let index = y * bytesPerRow + x * 4
                    let luminance = (
                        Int(pixels[index])
                            + Int(pixels[index + 1])
                            + Int(pixels[index + 2])
                    ) / 3
                    darkCornerPixels += luminance < 14 ? 1 : 0
                    cornerPixels += 1
                }
            }
        }

        let centerX = width / 2
        let centerY = height / 2
        let centerIndex = centerY * bytesPerRow + centerX * 4
        let centerLuminance = (
            Int(pixels[centerIndex])
                + Int(pixels[centerIndex + 1])
                + Int(pixels[centerIndex + 2])
        ) / 3
        return centerLuminance > 28
            && Double(darkCornerPixels) / Double(cornerPixels) > 0.55
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}
