import Foundation
import Testing
@testable import PanoWizard

struct CubeMapServiceTests {
    @Test("Exports and imports a requested real panorama")
    func requestedRealPanoramaRoundTrip() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let panoramaPath = environment["PANOWIZARD_CUBE_PANORAMA"],
              let mapPath = environment["PANOWIZARD_CUBE_MAP"],
              let roundTripPath = environment["PANOWIZARD_CUBE_ROUNDTRIP"] else {
            return
        }
        let service = CubeMapService()
        let panoramaURL = URL(fileURLWithPath: panoramaPath)
        try service.exportMap(
            panoramaURL: panoramaURL,
            nadirOverlayURL: nil,
            zenithOverlayURL: nil,
            nadirRetouchURL: nil,
            zenithRetouchURL: nil,
            to: URL(fileURLWithPath: mapPath)
        )
        try service.importMap(
            from: URL(fileURLWithPath: mapPath),
            panoramaURL: panoramaURL,
            to: URL(fileURLWithPath: roundTripPath)
        )
    }

    @Test("Exports the standard cross with correctly oriented face centers")
    func exportsStandardCross() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let panoramaURL = directory.appending(path: "panorama.png")
        let mapURL = directory.appending(path: "map.png")
        try directionalPanorama(width: 360, height: 180).writePNG(to: panoramaURL)

        try CubeMapService().exportMap(
            panoramaURL: panoramaURL,
            nadirOverlayURL: nil,
            zenithOverlayURL: nil,
            nadirRetouchURL: nil,
            zenithRetouchURL: nil,
            to: mapURL,
            faceSize: 33
        )

        let map = try RGBAImage(contentsOf: mapURL)
        #expect(map.width == 132)
        #expect(map.height == 99)
        #expect(color(map, tileX: 0, tileY: 1) == (255, 255, 0))
        #expect(color(map, tileX: 1, tileY: 1) == (255, 0, 0))
        #expect(color(map, tileX: 2, tileY: 1) == (0, 255, 0))
        #expect(color(map, tileX: 3, tileY: 1) == (0, 0, 255))
        #expect(color(map, tileX: 1, tileY: 0) == (0, 255, 255))
        #expect(color(map, tileX: 1, tileY: 2) == (255, 0, 255))
        #expect(map.pixel(x: 0, y: 0).a == 0)
    }

    @Test("Cube export includes the current pole retouch")
    func exportIncludesRetouch() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let panoramaURL = directory.appending(path: "panorama.png")
        let plateURL = directory.appending(path: "plate.png")
        let preparedURL = directory.appending(path: "prepared.png")
        let mapURL = directory.appending(path: "map.png")
        var panorama = RGBAImage(width: 64, height: 32)
        for y in 0..<panorama.height {
            for x in 0..<panorama.width {
                panorama.setPixel(Pixel(r: 0, g: 0, b: 0, a: 1), x: x, y: y)
            }
        }
        var plate = RGBAImage(width: 16, height: 16)
        for y in 0..<plate.height {
            for x in 0..<plate.width {
                plate.setPixel(Pixel(r: 1, g: 0, b: 0, a: 1), x: x, y: y)
            }
        }
        try panorama.writePNG(to: panoramaURL)
        try plate.writePNG(to: plateURL)
        try PoleRetouchService().prepareImportedPlate(
            from: plateURL,
            pole: .nadir,
            to: preparedURL,
            expectedSize: 16
        )

        try CubeMapService().exportMap(
            panoramaURL: panoramaURL,
            nadirOverlayURL: nil,
            zenithOverlayURL: nil,
            nadirRetouchURL: preparedURL,
            zenithRetouchURL: nil,
            to: mapURL,
            faceSize: 17
        )

        let map = try RGBAImage(contentsOf: mapURL)
        #expect(rgb(map.pixel(x: 25, y: 42)) == (255, 0, 0))
        #expect(rgb(map.pixel(x: 25, y: 25)) == (0, 0, 0))
    }

    @Test("Imports every cube face without holes")
    func importsStandardCross() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let panoramaURL = directory.appending(path: "panorama.png")
        let mapURL = directory.appending(path: "map.png")
        let importedURL = directory.appending(path: "imported.png")
        try directionalPanorama(width: 360, height: 180).writePNG(to: panoramaURL)
        let service = CubeMapService()
        try service.exportMap(
            panoramaURL: panoramaURL,
            nadirOverlayURL: nil,
            zenithOverlayURL: nil,
            nadirRetouchURL: nil,
            zenithRetouchURL: nil,
            to: mapURL,
            faceSize: 33
        )
        try service.importMap(
            from: mapURL,
            panoramaURL: panoramaURL,
            to: importedURL,
            faceSize: 33
        )

        let imported = try RGBAImage(contentsOf: importedURL)
        #expect(imported.width == 360)
        #expect(imported.height == 180)
        #expect(rgb(imported.pixel(x: 180, y: 90)) == (255, 0, 0))
        #expect(rgb(imported.pixel(x: 270, y: 90)) == (0, 255, 0))
        #expect(rgb(imported.pixel(x: 90, y: 90)) == (255, 255, 0))
        #expect(rgb(imported.pixel(x: 0, y: 90)) == (0, 0, 255))
        #expect(rgb(imported.pixel(x: 180, y: 0)) == (0, 255, 255))
        #expect(rgb(imported.pixel(x: 180, y: 179)) == (255, 0, 255))
        for y in stride(from: 0, to: imported.height, by: 9) {
            for x in stride(from: 0, to: imported.width, by: 9) {
                #expect(imported.pixel(x: x, y: y).a == 1)
            }
        }
    }

    @Test("Rejects a cube map with the wrong dimensions")
    func rejectsWrongDimensions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let panoramaURL = directory.appending(path: "panorama.png")
        let mapURL = directory.appending(path: "map.png")
        let destinationURL = directory.appending(path: "imported.png")
        try directionalPanorama(width: 32, height: 16).writePNG(to: panoramaURL)
        try RGBAImage(width: 7, height: 6).writePNG(to: mapURL)

        #expect(throws: CubeMapError.self) {
            try CubeMapService().importMap(
                from: mapURL,
                panoramaURL: panoramaURL,
                to: destinationURL,
                faceSize: 2
            )
        }
    }

    @Test("Rejects moved or transparent cube faces")
    func rejectsIncompleteFace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let panoramaURL = directory.appending(path: "panorama.png")
        let mapURL = directory.appending(path: "cube.png")
        let destinationURL = directory.appending(path: "imported.png")
        try directionalPanorama(width: 32, height: 16).writePNG(to: panoramaURL)
        var map = RGBAImage(width: 8, height: 6)
        for y in 0..<map.height {
            for x in 0..<map.width {
                map.setPixel(Pixel(r: 0, g: 0, b: 0, a: 1), x: x, y: y)
            }
        }
        map.setPixel(Pixel(r: 0, g: 0, b: 0, a: 0), x: 2, y: 0)
        try map.writePNG(to: mapURL)

        #expect(throws: CubeMapError.incompleteFace) {
            try CubeMapService().importMap(
                from: mapURL,
                panoramaURL: panoramaURL,
                to: destinationURL,
                faceSize: 2
            )
        }
    }

    private func directionalPanorama(width: Int, height: Int) -> RGBAImage {
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            let latitude = (0.5 - (Double(y) + 0.5) / Double(height)) * .pi
            let directionY = sin(latitude)
            let horizontalRadius = cos(latitude)
            for x in 0..<width {
                let longitude = (
                    (Double(x) + 0.5) / Double(width) - 0.5
                ) * 2 * .pi
                let directionX = sin(longitude) * horizontalRadius
                let directionZ = cos(longitude) * horizontalRadius
                let absoluteX = abs(directionX)
                let absoluteY = abs(directionY)
                let absoluteZ = abs(directionZ)
                let color: Pixel
                if absoluteY >= absoluteX, absoluteY >= absoluteZ {
                    color = directionY >= 0
                        ? Pixel(r: 0, g: 1, b: 1, a: 1)
                        : Pixel(r: 1, g: 0, b: 1, a: 1)
                } else if absoluteX >= absoluteZ {
                    color = directionX >= 0
                        ? Pixel(r: 0, g: 1, b: 0, a: 1)
                        : Pixel(r: 1, g: 1, b: 0, a: 1)
                } else {
                    color = directionZ >= 0
                        ? Pixel(r: 1, g: 0, b: 0, a: 1)
                        : Pixel(r: 0, g: 0, b: 1, a: 1)
                }
                image.setPixel(color, x: x, y: y)
            }
        }
        return image
    }

    private func color(
        _ image: RGBAImage,
        tileX: Int,
        tileY: Int
    ) -> (UInt8, UInt8, UInt8) {
        rgb(image.pixel(x: tileX * 33 + 16, y: tileY * 33 + 16))
    }

    private func rgb(_ pixel: Pixel) -> (UInt8, UInt8, UInt8) {
        (
            UInt8((pixel.r * 255).rounded()),
            UInt8((pixel.g * 255).rounded()),
            UInt8((pixel.b * 255).rounded())
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "PanoWizard-CubeMap-Tests/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}
