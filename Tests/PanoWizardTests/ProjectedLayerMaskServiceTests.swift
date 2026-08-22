import Testing
@testable import PanoWizard

struct ProjectedLayerMaskServiceTests {
    @Test
    func insetsAlphaByTheMinimumNeighboringPixel() {
        let alpha: [UInt8] = [
            255, 255, 255, 255, 255,
            255, 255, 255, 255, 255,
            255, 255,   0, 255, 255,
            255, 255, 255, 255, 255,
            255, 255, 255, 255, 255
        ]

        let inset = ProjectedLayerMaskService.insetAlphaByOnePixel(
            alpha,
            width: 5,
            height: 5
        )

        #expect(inset == [
            255, 255, 255, 255, 255,
            255,   0,   0,   0, 255,
            255,   0,   0,   0, 255,
            255,   0,   0,   0, 255,
            255, 255, 255, 255, 255
        ])
    }
}
