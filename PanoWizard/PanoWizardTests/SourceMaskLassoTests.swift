import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PanoWizard

@Suite("Source mask lasso")
struct SourceMaskLassoTests {
    private let width = 64
    private let height = 48
    private let square = [
        MaskPoint(x: 0.25, y: 0.25), MaskPoint(x: 0.75, y: 0.25),
        MaskPoint(x: 0.75, y: 0.75), MaskPoint(x: 0.25, y: 0.75)
    ]

    @Test("Geometry uses normalized oriented-image coordinates and closes automatically")
    func geometry() throws {
        let points = [MaskPoint(x: 0.1, y: 0.2), MaskPoint(x: 0.5, y: 0.2),
                      MaskPoint(x: 0.5, y: 0.6), MaskPoint(x: 0.1, y: 0.6)]
        let path = try #require(SourceMaskRasterizer.lassoPath(points: points, width: 100, height: 50))
        #expect(abs(path.boundingBoxOfPath.minX - 10) < 0.001)
        #expect(abs(path.boundingBoxOfPath.minY - 20) < 0.001)
        #expect(abs(path.boundingBoxOfPath.width - 40) < 0.001)
        #expect(abs(path.boundingBoxOfPath.height - 20) < 0.001)
        var closes = 0
        path.applyWithBlock { if $0.pointee.type == .closeSubpath { closes += 1 } }
        #expect(closes == 1)
    }

    @Test("Empty, repeated, collinear, tiny and nonfinite paths leave the mask unchanged")
    func degeneratePaths() {
        let existing = Data([1, 2, 3])
        let paths: [[MaskPoint]] = [
            [], [MaskPoint(x: 0.5, y: 0.5)],
            Array(repeating: MaskPoint(x: 0.5, y: 0.5), count: 5),
            [MaskPoint(x: 0, y: 0), MaskPoint(x: 0.5, y: 0.5), MaskPoint(x: 1, y: 1)],
            [MaskPoint(x: 0, y: 0), MaskPoint(x: 0.001, y: 0), MaskPoint(x: 0, y: 0.001)],
            [MaskPoint(x: .nan, y: 0), MaskPoint(x: 1, y: 0), MaskPoint(x: 0, y: 1)],
            [MaskPoint(x: 0, y: .infinity), MaskPoint(x: 1, y: 0), MaskPoint(x: 0, y: 1)]
        ]
        for points in paths {
            #expect(SourceMaskRasterizer.applyingLasso(
                points: points, erasing: false, to: existing, width: width, height: height
            ) == existing)
        }
        #expect(SourceMaskRasterizer.applyingLasso(
            points: square, erasing: false, to: existing, width: 0, height: height
        ) == existing)
    }

    @Test("Include and Exclude fill sharply without fractional alpha", arguments: [false, true])
    func sharpFill(protected: Bool) throws {
        let triangle = [MaskPoint(x: 0.1, y: 0.1), MaskPoint(x: 0.9, y: 0.3), MaskPoint(x: 0.3, y: 0.9)]
        let data = try #require(lasso(triangle, protected: protected))
        let image = try decode(data)
        #expect(image.width == width)
        #expect(image.height == height)
        let pixels = bytes(image)
        #expect(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 0 || pixels[$0] == 255 })
        let inside = pixel(data, x: 0.3, y: 0.3)
        #expect(inside[3] == 255)
        #expect(protected ? inside[1] > inside[0] : inside[0] > inside[1])
        #expect(pixel(data, x: 0.9, y: 0.9)[3] == 0)
    }

    @Test("Concave polygons fill their interior, not their bounding rectangle")
    func concaveFill() {
        let points = [MaskPoint(x: 0.1, y: 0.1), MaskPoint(x: 0.9, y: 0.1),
                      MaskPoint(x: 0.9, y: 0.4), MaskPoint(x: 0.4, y: 0.4),
                      MaskPoint(x: 0.4, y: 0.9), MaskPoint(x: 0.1, y: 0.9)]
        let data = lasso(points)
        #expect(pixel(data, x: 0.2, y: 0.2)[3] == 255)
        #expect(pixel(data, x: 0.2, y: 0.7)[3] == 255)
        #expect(pixel(data, x: 0.7, y: 0.7)[3] == 0)
    }

    @Test("Self-intersections use even-odd filling rather than disappearing")
    func selfIntersection() {
        let bow = [MaskPoint(x: 0.1, y: 0.1), MaskPoint(x: 0.9, y: 0.9),
                   MaskPoint(x: 0.1, y: 0.9), MaskPoint(x: 0.9, y: 0.1)]
        let data = lasso(bow)
        #expect(pixel(data, x: 0.5, y: 0.2)[3] == 255)
        #expect(pixel(data, x: 0.5, y: 0.8)[3] == 255)
        #expect(pixel(data, x: 0.15, y: 0.5)[3] == 0)
    }

    @Test("Outside release coordinates are clipped by the canvas, not clamped per point")
    func outsideImage() {
        let points = [MaskPoint(x: -1, y: -1), MaskPoint(x: 2, y: -1),
                      MaskPoint(x: 2, y: 2), MaskPoint(x: -1, y: 2)]
        let data = lasso(points)
        for point in [MaskPoint(x: 0.01, y: 0.01), MaskPoint(x: 0.99, y: 0.99)] {
            #expect(pixel(data, x: point.x, y: point.y)[3] == 255)
        }
        #expect(lasso(points, erasing: true, existing: data) == nil)
    }

    @Test("Lasso and Paint overwrite each other in both mask modes", arguments: [false, true])
    func latestOperationWins(protected: Bool) {
        let center = [MaskPoint(x: 0.5, y: 0.5)]
        // Start with Paint in the opposite mask, then replace it with Lasso.
        var opposite = SourceMaskRasterizer.applying(
            stroke: center, radius: 10, erasing: false, protectedArea: !protected,
            to: nil, width: width, height: height
        )
        var chosen = lasso(square, protected: protected)
        opposite = lasso(square, erasing: true, existing: opposite)
        #expect(pixel(chosen, x: 0.5, y: 0.5)[3] == 255)
        #expect(pixel(opposite, x: 0.5, y: 0.5)[3] == 0)
        // Paint in the opposite mode replaces the lasso in the same raster masks.
        opposite = SourceMaskRasterizer.applying(
            stroke: center, radius: 4, erasing: false, protectedArea: !protected,
            to: opposite, width: width, height: height
        )
        chosen = SourceMaskRasterizer.applying(
            stroke: center, radius: 4, erasing: true,
            to: chosen, width: width, height: height
        )
        #expect(pixel(opposite, x: 0.5, y: 0.5)[3] == 255)
        #expect(pixel(chosen, x: 0.5, y: 0.5)[3] == 0)
        #expect(pixel(chosen, x: 0.3, y: 0.3)[3] == 255)
        // Another lasso replaces that painted region again.
        chosen = lasso(square, protected: protected, existing: chosen)
        opposite = lasso(square, erasing: true, existing: opposite)
        #expect(pixel(chosen, x: 0.5, y: 0.5)[3] == 255)
        #expect(pixel(opposite, x: 0.5, y: 0.5)[3] == 0)
    }

    @Test("Lasso masks remain aligned through existing image rotation")
    func rotation() throws {
        let original = try #require(lasso([
            MaskPoint(x: 0.1, y: 0.2), MaskPoint(x: 0.3, y: 0.2),
            MaskPoint(x: 0.3, y: 0.4), MaskPoint(x: 0.1, y: 0.4)
        ]))
        let rotated = try #require(try SourceImageRaster.rotatePNGLeft(original))
        #expect(try decode(rotated).width == height)
        #expect(try decode(rotated).height == width)
        #expect(pixel(rotated, x: 0.3, y: 0.8)[3] == 255)
        #expect(pixel(rotated, x: 0.8, y: 0.3)[3] == 0)
        var restored = rotated
        for _ in 0..<3 { restored = try #require(try SourceImageRaster.rotatePNGLeft(restored)) }
        #expect(try bytes(decode(restored)) == bytes(decode(original)))
    }

    @Test("A completed lasso uses one existing paired-mask undo operation")
    @MainActor
    func singleUndo() throws {
        let image = SourceImage(
            url: URL(fileURLWithPath: "/tmp/\(UUID()).jpg"), captureDate: nil,
            pixelWidth: width, pixelHeight: height, cameraModel: nil,
            lens: LensDescription(model: nil, focalLengthIn35mm: nil, kind: .unknown)
        )
        let model = AppModel.live(project: PanoProject(images: [image]))
        #expect(model.sourceMaskTool == .brush)
        let initialGreen = SourceMaskRasterizer.applying(
            stroke: [MaskPoint(x: 0.5, y: 0.5)], radius: 8,
            erasing: false, protectedArea: true, to: nil, width: width, height: height
        )
        model.setSourceMasks(red: nil, green: initialGreen, for: image.id)
        let red = lasso(square)
        let green = lasso(square, erasing: true, existing: initialGreen)
        model.setSourceMasks(red: red, green: green, for: image.id)
        model.undoMask()
        #expect(model.maskDataByImageID[image.id] == nil)
        #expect(model.protectedMaskDataByImageID[image.id] == initialGreen)
        model.undoMask()
        #expect(!model.canUndoMask)
        #expect(model.protectedMaskDataByImageID[image.id] == nil)
    }

    private func lasso(_ points: [MaskPoint], erasing: Bool = false,
                       protected: Bool = false, existing: Data? = nil) -> Data? {
        SourceMaskRasterizer.applyingLasso(
            points: points, erasing: erasing, protectedArea: protected,
            to: existing, width: width, height: height
        )
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private func pixel(_ data: Data?, x: CGFloat, y: CGFloat) -> [UInt8] {
        guard let data, let image = try? decode(data) else { return [0, 0, 0, 0] }
        let pixels = bytes(image)
        let offset = (Int(y * CGFloat(image.height)) * image.width
                      + Int(x * CGFloat(image.width))) * 4
        return Array(pixels[offset..<(offset + 4)])
    }
}
