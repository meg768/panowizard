import Testing
@testable import PanoWizard

@Suite("Spherical panorama math")
struct SphericalPanoramaMathTests {
    @Test("Pitch correction preserves an off-center vertical anchor")
    func pitchCorrectionPreservesVerticalAnchor() {
        let initialPitch: Float = 0
        let fixedLatitude: Float = 21 * .pi / 180
        let currentLatitude: Float = 16 * .pi / 180

        let correctedPitch = SphericalPanoramaMath.correctedPitch(
            initialPitch,
            fixedLatitude: fixedLatitude,
            currentLatitude: currentLatitude
        )
        let resultingLatitude = currentLatitude
            - (correctedPitch - initialPitch)

        #expect(correctedPitch < initialPitch)
        #expect(abs(resultingLatitude - fixedLatitude) < 0.000_001)
    }
}
