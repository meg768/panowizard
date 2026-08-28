import AppKit
import Testing
@testable import PanoWizard

@Suite("ImageSurfaceInteractionTests")
struct ImageSurfaceInteractionTests {
    @Test
    func mapsEditorModifiersToNavigationEditAndRemoval() {
        #expect(ImageSurfaceInteraction(modifierFlags: []) == .navigate)
        #expect(
            ImageSurfaceInteraction(modifierFlags: [.option]) == .navigate
        )
        #expect(
            ImageSurfaceInteraction(modifierFlags: [.command]) == .edit
        )
        #expect(
            ImageSurfaceInteraction(
                modifierFlags: [.command, .option]
            ) == .remove
        )
    }

    @Test
    func normalizesDominantPhysicalScrollAxis() {
        #expect(ImageSurfaceScroll.dominantDelta(
            horizontal: 2,
            vertical: -8,
            isDirectionInverted: false
        ) == -8)
        #expect(ImageSurfaceScroll.dominantDelta(
            horizontal: 9,
            vertical: 3,
            isDirectionInverted: true
        ) == -9)
    }

}
