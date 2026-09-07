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

        #expect(bytes[center + 1] > 180)
        #expect(bytes[center + 2] < 80)
        #expect(bytes[outsideHorizon] < 80)
        #expect(bytes[outsideHorizon + 2] > 180)
        #expect(bytes[3] == 0)
    }
}
