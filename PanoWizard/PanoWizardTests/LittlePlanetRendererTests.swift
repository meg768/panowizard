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
            let expectedLongitude = atan2(dx, dy)
                + settings.rotationDegrees * .pi / 180.0
            let direction = projection.sourceDirection(outputX: x, outputY: y)

            #expect(direction.latitude == expectedLatitude)
            #expect(direction.longitude == expectedLongitude)
        }
    }

    @Test("Places the source viewport center direction at twelve o'clock")
    func sourceViewportCenterIsAtTop() {
        let side = 200
        let radius = Double(side) / 2.0 - 2.0
        let horizon = 0.5
        let cases = [
            (sourceLongitude: 73.0, centerLongitude: 0.0, centerLatitude: -90.0),
            (sourceLongitude: 130.0, centerLongitude: 47.0, centerLatitude: -24.0),
            (sourceLongitude: -20.0, centerLongitude: -115.0, centerLatitude: 35.0),
        ]

        for testCase in cases {
            var settings = LittlePlanetSettings()
            settings.centerLongitudeDegrees = testCase.centerLongitude
            settings.centerLatitudeDegrees = testCase.centerLatitude
            settings.rotationDegrees = LittlePlanetProjection.rotationDegrees(
                placingSourceLongitudeAtTop: testCase.sourceLongitude,
                centerLongitudeDegrees: testCase.centerLongitude,
                centerLatitudeDegrees: testCase.centerLatitude
            )

            let sourceLongitude = testCase.sourceLongitude * .pi / 180.0
            let centerLongitude = testCase.centerLongitude * .pi / 180.0
            let centerLatitude = testCase.centerLatitude * .pi / 180.0
            let centerTilt = -(centerLatitude + .pi / 2.0)
            let longitudeDifference = sourceLongitude - centerLongitude
            let localZ = sin(centerTilt) * cos(longitudeDifference)
            let localLatitude = asin(min(max(localZ, -1.0), 1.0))
            let stereographicRadius = tan((localLatitude + .pi / 2.0) / 2.0)
            let outputY = Double(side) / 2.0
                + stereographicRadius * horizon * radius

            let direction = LittlePlanetProjection(side: side, settings: settings)
                .sourceDirection(
                    outputX: Double(side) / 2.0,
                    outputY: outputY
                )
            let longitudeDifferenceAtTop = atan2(
                sin(direction.longitude - sourceLongitude),
                cos(direction.longitude - sourceLongitude)
            )

            #expect(abs(direction.latitude) < 1e-12)
            #expect(abs(longitudeDifferenceAtTop) < 1e-12)
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
        #expect(Int(bytes[bottom]) > Int(bytes[top]) + 60)

    }

}
