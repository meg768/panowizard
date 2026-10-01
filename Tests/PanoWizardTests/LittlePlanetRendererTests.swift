import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PanoWizard

@Suite("Little Planet renderer")
struct LittlePlanetRendererTests {
    @Test("Places nadir at the center, sky outside the horizon, and preserves transparency")
    func nadirAndTransparency() throws {
        let width = 64
        let height = 32
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if y < height / 2 {
                    pixels[offset] = 20
                    pixels[offset + 1] = 60
                    pixels[offset + 2] = 220
                } else {
                    pixels[offset] = 30
                    pixels[offset + 1] = 210
                    pixels[offset + 2] = 40
                }
            }
        }
        let data = Data(pixels)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let sourceImage = try #require(CGImage(
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
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-LittlePlanet-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.png")
        try LittlePlanetRenderer.writePNG(sourceImage, to: sourceURL)

        let source = try LittlePlanetSource(url: sourceURL)
        let result = try LittlePlanetRenderer.render(
            source: source,
            side: 100,
            settings: LittlePlanetSettings()
        )
        let resultData = try #require(result.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(resultData))
        let center = (50 * 100 + 50) * 4
        let outsideHorizon = (50 * 100 + 85) * 4
        let nearEdge = (50 * 100 + 2) * 4

        #expect(bytes[center + 1] > 180)
        #expect(bytes[center + 2] < 80)
        #expect(bytes[outsideHorizon] < 80)
        #expect(bytes[outsideHorizon + 2] > 180)
        #expect(bytes[nearEdge + 3] >= 248)
        #expect(bytes[3] == 0)

        var featheredSettings = LittlePlanetSettings()
        featheredSettings.edgeFeatherPercent = 10
        let feathered = try LittlePlanetRenderer.render(
            source: source,
            side: 100,
            settings: featheredSettings
        )
        let featheredData = try #require(feathered.dataProvider?.data)
        let featheredBytes = try #require(CFDataGetBytePtr(featheredData))
        #expect(featheredBytes[nearEdge + 3] > 0)
        #expect(featheredBytes[nearEdge + 3] < 128)

        var whiteSettings = LittlePlanetSettings()
        whiteSettings.background = .white
        let white = try LittlePlanetRenderer.render(
            source: source,
            side: 100,
            settings: whiteSettings
        )
        let whiteData = try #require(white.dataProvider?.data)
        let whiteBytes = try #require(CFDataGetBytePtr(whiteData))
        #expect(whiteBytes[0] == 255)
        #expect(whiteBytes[1] == 255)
        #expect(whiteBytes[2] == 255)
        #expect(whiteBytes[3] == 255)

        var blackSettings = LittlePlanetSettings()
        blackSettings.background = .black
        let black = try LittlePlanetRenderer.render(
            source: source,
            side: 100,
            settings: blackSettings
        )
        let blackData = try #require(black.dataProvider?.data)
        let blackBytes = try #require(CFDataGetBytePtr(blackData))
        #expect(blackBytes[0] == 0)
        #expect(blackBytes[1] == 0)
        #expect(blackBytes[2] == 0)
        #expect(blackBytes[3] == 255)

    }

}
