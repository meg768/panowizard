import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PanoWizard

@Suite("Source image rotation")
struct SourceImageRasterTests {
    @Test("Manual quarter turns swap dimensions and return to the source")
    func quarterTurns() throws {
        let source = try testImage(width: 3, height: 2)
        let left = try #require(SourceImageRaster.rotated(source, by: .left90))
        #expect(left.width == 2)
        #expect(left.height == 3)
        let sourceBytes = renderedBytes(source)
        let leftBytes = renderedBytes(left)
        for y in 0..<left.height {
            for x in 0..<left.width {
                let sourceX = source.width - 1 - y
                let sourceY = x
                #expect(
                    pixel(leftBytes, width: left.width, x: x, y: y)
                        == pixel(
                            sourceBytes,
                            width: source.width,
                            x: sourceX,
                            y: sourceY
                        )
                )
            }
        }

        var rotated = source
        for _ in 0..<4 {
            rotated = try #require(
                SourceImageRaster.rotated(rotated, by: .left90)
            )
        }
        #expect(rotated.width == source.width)
        #expect(rotated.height == source.height)
        #expect(renderedBytes(rotated) == renderedBytes(source))
    }

    @Test("PNG masks rotate without losing their alpha")
    func rotatesMaskPNG() throws {
        let data = try pngData(testImage(width: 3, height: 2))
        let rotatedData = try #require(
            try SourceImageRaster.rotatePNGLeft(data)
        )
        let source = try #require(
            CGImageSourceCreateWithData(rotatedData as CFData, nil)
        )
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(image.width == 2)
        #expect(image.height == 3)
        #expect(renderedBytes(image).contains { $0 > 0 })
    }

    @Test("Selecting a source opens its scoped mask editor")
    @MainActor
    func perSourceUndo() {
        let first = sourceImage()
        let second = sourceImage()
        let model = AppModel.live(project: PanoProject(images: [first, second]))
        let firstMask = Data([1, 2, 3])
        let secondMask = Data([4, 5, 6])

        #expect(model.isSourceMaskEditing)
        model.setSourceMasks(red: firstMask, green: nil, for: first.id)
        model.setSourceMasks(red: secondMask, green: nil, for: first.id)
        model.undoMask()
        #expect(model.maskDataByImageID[first.id] == firstMask)

        model.selectSourceImage(second.id)
        #expect(model.isSourceMaskEditing)
        #expect(!model.canUndoMask)

        model.selection = .panorama
        #expect(!model.isSourceMaskEditing)

        model.selectSourceImage(first.id)
        #expect(model.isSourceMaskEditing)
        #expect(model.canUndoMask)
        model.undoMask()
        #expect(model.maskDataByImageID[first.id] == nil)
    }

    @Test("Image rotation keeps the mask and its undo history aligned")
    @MainActor
    func rotationKeepsMaskHistory() throws {
        let image = sourceImage()
        let firstMask = try pngData(testImage(width: 3, height: 2))
        let secondMask = try pngData(testImage(width: 3, height: 2))
        let model = AppModel.live(project: PanoProject(images: [image]))
        model.setSourceMasks(red: firstMask, green: nil, for: image.id)
        model.setSourceMasks(red: secondMask, green: firstMask, for: image.id)

        model.rotateSourceImageLeft(image.id)

        #expect(model.project.images[0].rotation == .left90)
        #expect(model.project.images[0].orientedPixelWidth == 2)
        #expect(model.project.images[0].orientedPixelHeight == 3)
        #expect(try dimensions(model.maskDataByImageID[image.id]) == [2, 3])
        #expect(try dimensions(model.protectedMaskDataByImageID[image.id]) == [2, 3])

        model.undoMask()
        #expect(try dimensions(model.maskDataByImageID[image.id]) == [2, 3])
        #expect(model.protectedMaskDataByImageID[image.id] == nil)
    }

    @Test("Older source records default to no manual rotation")
    func legacyRotationDefault() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "url": "file:///tmp/source.nef",
          "pixelWidth": 3872,
          "pixelHeight": 2592,
          "cameraModel": "NIKON D80",
          "lens": {"model":"Sigma 8mm","focalLengthIn35mm":8,"kind":"fisheye"},
          "direction": "horizontal",
          "role": "automatic",
          "isEnabled": true
        }
        """
        let image = try JSONDecoder().decode(
            SourceImage.self,
            from: Data(json.utf8)
        )

        #expect(image.rotation == .none)
        #expect(image.orientedPixelWidth == 3872)
        #expect(image.orientedPixelHeight == 2592)
    }

    @Test("A failed trash move keeps the source in the project")
    @MainActor
    func failedTrashMoveIsNonDestructive() {
        let image = sourceImage()
        let model = AppModel.live(project: PanoProject(images: [image]))

        #expect(throws: (any Error).self) {
            try model.moveSourceImageToTrash(image.id)
        }

        #expect(model.project.images.map(\.id) == [image.id])
        #expect(model.phase == .ready)
    }

    private func sourceImage() -> SourceImage {
        SourceImage(
            url: URL(fileURLWithPath: "/tmp/\(UUID()).jpg"),
            captureDate: nil,
            pixelWidth: 3,
            pixelHeight: 2,
            cameraModel: nil,
            lens: LensDescription(
                model: nil,
                focalLengthIn35mm: nil,
                kind: .unknown
            )
        )
    }

    private func testImage(width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = UInt8(30 + x * 50)
                pixels[offset + 1] = UInt8(40 + y * 70)
                pixels[offset + 2] = UInt8(80 + (x + y) * 20)
                pixels[offset + 3] = UInt8(120 + x * 30 + y * 20)
            }
        }
        let provider = try #require(
            CGDataProvider(data: Data(pixels) as CFData)
        )
        return try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func renderedBytes(_ image: CGImage) -> [UInt8] {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return pixels
    }

    private func pixel(
        _ bytes: [UInt8],
        width: Int,
        x: Int,
        y: Int
    ) -> ArraySlice<UInt8> {
        let offset = (y * width + x) * 4
        return bytes[offset..<(offset + 4)]
    }

    private func dimensions(_ data: Data?) throws -> [Int] {
        let data = try #require(data)
        let source = try #require(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return [image.width, image.height]
    }

    private func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
