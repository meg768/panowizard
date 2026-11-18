import AppKit
import Testing
@testable import PanoWizard

@Suite("Little Planet dialog interaction")
struct LittlePlanetExportSheetInteractionTests {
    @Test("Center marker clamps to every viewport edge and corner")
    func clampsCenterMarker() {
        let size = CGSize(width: 360, height: 360)

        #expect(
            LittlePlanetPanoramaSelection.clampedLocation(
                CGPoint(x: -40, y: -25),
                in: size
            ) == CGPoint(x: 0, y: 0)
        )
        #expect(
            LittlePlanetPanoramaSelection.clampedLocation(
                CGPoint(x: 400, y: -25),
                in: size
            ) == CGPoint(x: 360, y: 0)
        )
        #expect(
            LittlePlanetPanoramaSelection.clampedLocation(
                CGPoint(x: -40, y: 390),
                in: size
            ) == CGPoint(x: 0, y: 360)
        )
        #expect(
            LittlePlanetPanoramaSelection.clampedLocation(
                CGPoint(x: 400, y: 390),
                in: size
            ) == CGPoint(x: 360, y: 360)
        )
    }

    @Test("Full panorama selection maps sky, horizon and ground without hidden panning")
    func mapsMarkerToFullPanorama() {
        let size = CGSize(width: 280, height: 140)
        for (point, longitude, latitude) in [
            (CGPoint(x: 70, y: 0), 90.0, 90.0),
            (CGPoint(x: 140, y: 70), 180.0, 0.0),
            (CGPoint(x: 210, y: 140), 270.0, -90.0),
            (CGPoint(x: 500, y: -50), 0.0, 90.0)
        ] {
            let coordinates = LittlePlanetPanoramaSelection.sourceCoordinates(at: point, viewportSize: size)
            #expect(abs(coordinates.longitudeDegrees - longitude) < 1e-12)
            #expect(abs(coordinates.latitudeDegrees - latitude) < 1e-12)
        }
    }

    @MainActor @Test("Reset recovers the default planet from a tilted custom composition")
    func resetCustomComposition() {
        let controller = LittlePlanetExportController()
        controller.settings.centerLongitudeDegrees = 115
        controller.settings.centerLatitudeDegrees = -12
        controller.settings.rotationDegrees = 48
        controller.settings.horizonPercent = 63
        controller.reset()
        #expect(controller.settings == LittlePlanetSettings())
    }
}
