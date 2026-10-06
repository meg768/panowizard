import AppKit
import Testing
@testable import PanoWizard

@Suite("Little Planet dialog interaction")
struct LittlePlanetExportSheetInteractionTests {
    @Test("Option selects center drag without changing normal drag")
    func dragModes() {
        #expect(LittlePlanetPanoramaDragMode(modifierFlags: []) == .pan)
        #expect(
            LittlePlanetPanoramaDragMode(modifierFlags: [.option]) == .center
        )
        #expect(
            LittlePlanetPanoramaDragMode(
                modifierFlags: [.command, .option]
            ) == .center
        )
    }

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

    @Test("Clamped marker maps through the current panorama pan")
    func mapsClampedMarkerToSource() {
        let viewportSize = CGSize(width: 360, height: 360)
        let panoramaWidth: CGFloat = 720
        let panTurns = 0.125
        let location = LittlePlanetPanoramaSelection.clampedLocation(
            CGPoint(x: 500, y: -50),
            in: viewportSize
        )
        let coordinates = LittlePlanetPanoramaSelection.sourceCoordinates(
            at: location,
            viewportSize: viewportSize,
            panoramaWidth: panoramaWidth,
            panTurns: panTurns
        )

        #expect(location == CGPoint(x: 360, y: 0))
        #expect(abs(coordinates.longitudeDegrees - 45) < 1e-12)
        #expect(abs(coordinates.latitudeDegrees - 90) < 1e-12)
    }
}
