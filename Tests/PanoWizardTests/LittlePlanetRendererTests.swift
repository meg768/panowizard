import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PanoWizard

@Suite("Little Planet renderer")
struct LittlePlanetRendererTests {
    @Test("Loads nadir and zenith retouches into the Little Planet source")
    func loadsPoleRetouches() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-LittlePlanet-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let panoramaURL = directory.appending(path: "panorama.png")
        let nadirSourceURL = directory.appending(path: "nadir-source.png")
        let zenithSourceURL = directory.appending(path: "zenith-source.png")
        let nadirRetouchURL = directory.appending(path: "nadir-retouch.png")
        let zenithRetouchURL = directory.appending(path: "zenith-retouch.png")
        try LittlePlanetRenderer.writePNG(
            solidImage(width: 360, height: 180, color: (0, 0, 0, 255)),
            to: panoramaURL
        )
        try LittlePlanetRenderer.writePNG(
            solidImage(width: 64, height: 64, color: (255, 0, 0, 255)),
            to: nadirSourceURL
        )
        try LittlePlanetRenderer.writePNG(
            solidImage(width: 64, height: 64, color: (0, 0, 255, 255)),
            to: zenithSourceURL
        )
        try PoleRetouchService().prepareImportedPlate(
            from: nadirSourceURL,
            pole: .nadir,
            to: nadirRetouchURL,
            expectedSize: 64
        )
        try PoleRetouchService().prepareImportedPlate(
            from: zenithSourceURL,
            pole: .zenith,
            to: zenithRetouchURL,
            expectedSize: 64
        )

        let source = try LittlePlanetSource(
            panoramaURL: panoramaURL,
            nadirRetouchURL: nadirRetouchURL,
            zenithRetouchURL: zenithRetouchURL
        )
        let nadir = pixel(source, x: 180, y: 0)
        let zenith = pixel(source, x: 180, y: 179)
        #expect(nadir.0 >= 248 && nadir.1 <= 7 && nadir.2 <= 7)
        #expect(zenith.0 <= 7 && zenith.1 <= 7 && zenith.2 >= 248)
    }

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

    private func solidImage(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8, UInt8)
    ) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = color.0
            pixels[offset + 1] = color.1
            pixels[offset + 2] = color.2
            pixels[offset + 3] = color.3
        }
        let data = Data(pixels)
        let provider = try #require(CGDataProvider(data: data as CFData))
        return try #require(CGImage(
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
    }

    private func pixel(
        _ source: LittlePlanetSource,
        x: Int,
        y: Int
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        let offset = (y * source.width + x) * 4
        return (
            source.pixels[offset], source.pixels[offset + 1],
            source.pixels[offset + 2], source.pixels[offset + 3]
        )
    }
}
