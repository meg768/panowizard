import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PanoWizard

@Suite("Little Planet renderer")
struct LittlePlanetRendererTests {
    @Test("Default center preserves the established projection coordinates")
    func defaultCenterCoordinates() {
        let side = 100
        let settings = LittlePlanetSettings()
        let projection = LittlePlanetProjection(side: side, settings: settings)

        for (x, y) in [(0.5, 0.5), (50.5, 50.5), (99.5, 71.5)] {
            let radius = Double(side) / 2.0 - 2.0
            let dx = (x - Double(side) / 2.0) / radius
            let dy = (y - Double(side) / 2.0) / radius
            let expectedLatitude = 2.0 * atan(
                hypot(dx, dy) / (settings.horizonPercent / 100.0)
            ) - .pi / 2.0
            let expectedLongitude = atan2(dx, -dy)
                + settings.rotationDegrees * .pi / 180.0
            let direction = projection.sourceDirection(outputX: x, outputY: y)

            #expect(direction.latitude == expectedLatitude)
            #expect(direction.longitude == expectedLongitude)
        }
    }

    @Test("A selected sphere direction becomes the new geometric center")
    func recenteredDirection() {
        let side = 100
        var settings = LittlePlanetSettings()
        settings.rotationDegrees = 31
        settings.centerLongitudeDegrees = 47
        settings.centerLatitudeDegrees = -24

        let original = LittlePlanetProjection(side: side, settings: settings)
        let selected = original.sourceDirection(outputX: 78, outputY: 36)
        settings.centerLongitudeDegrees = selected.longitude * 180 / .pi
        settings.centerLatitudeDegrees = selected.latitude * 180 / .pi

        let recentered = LittlePlanetProjection(side: side, settings: settings)
            .sourceDirection(outputX: 50, outputY: 50)
        let longitudeDifference = atan2(
            sin(recentered.longitude - selected.longitude),
            cos(recentered.longitude - selected.longitude)
        )

        #expect(abs(recentered.latitude - selected.latitude) < 1e-12)
        #expect(abs(longitudeDifference) < 1e-12)
    }

    @Test("Places nadir at the center with the correct output orientation")
    func squareProjection() throws {
        let width = 64
        let height = 32
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(x * 4)
                if y < height / 2 {
                    pixels[offset + 1] = 60
                    pixels[offset + 2] = 220
                } else {
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
        let top = (10 * 100 + 60) * 4
        let bottom = (89 * 100 + 60) * 4

        #expect(bytes[center + 1] > 180)
        #expect(bytes[center + 2] < 80)
        #expect(bytes[outsideHorizon + 2] > 180)
        #expect(bytes[2] > 180)
        #expect(bytes[3] == 255)
        #expect(Int(bytes[top]) > Int(bytes[bottom]) + 60)

    }

}
