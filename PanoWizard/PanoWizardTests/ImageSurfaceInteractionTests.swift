import AppKit
import Testing
@testable import PanoWizard

@Suite("ImageSurfaceInteractionTests")
struct ImageSurfaceInteractionTests {
    @Test
    func mapsEditorModifiersToNavigationEditAndRemoval() {
        #expect(ImageSurfaceInteraction(modifierFlags: []) == .navigate)
        #expect(
            ImageSurfaceInteraction(modifierFlags: [.command]) == .navigate
        )
        #expect(
            ImageSurfaceInteraction(modifierFlags: [.option]) == .edit
        )
        #expect(
            ImageSurfaceInteraction(
                modifierFlags: [.command, .option]
            ) == .remove
        )
    }

    @Test
    func mapsScrollToPanOrCommandVerticalZoom() {
        #expect(ImageSurfaceScroll.intent(
            horizontal: 2,
            vertical: -8,
            isDirectionInverted: false,
            modifierFlags: []
        ) == .pan(horizontal: 2, vertical: -8))
        #expect(ImageSurfaceScroll.intent(
            horizontal: 2,
            vertical: -8,
            isDirectionInverted: false,
            modifierFlags: [.command]
        ) == .zoom(-8))
        #expect(ImageSurfaceScroll.intent(
            horizontal: 2,
            vertical: -8,
            isDirectionInverted: true,
            modifierFlags: [.command]
        ) == .zoom(8))
        #expect(ImageSurfaceScroll.intent(
            horizontal: 9,
            vertical: 3,
            isDirectionInverted: true,
            modifierFlags: [.command]
        ) == .ignore)
    }

    @Test
    func keepsOneAnchorThroughDirectAndMomentumScrollPhases() {
        var gesture = ImageSurfaceScrollGesture()

        let directBegin = gesture.beginsZoom(
            phase: .began,
            momentumPhase: []
        )
        let directChange = gesture.beginsZoom(
            phase: .changed,
            momentumPhase: []
        )
        let directEnd = gesture.beginsZoom(
            phase: .ended,
            momentumPhase: []
        )
        let momentumBegin = gesture.beginsZoom(
            phase: [],
            momentumPhase: .began
        )
        let momentumChange = gesture.beginsZoom(
            phase: [],
            momentumPhase: .changed
        )
        let momentumEnd = gesture.beginsZoom(
            phase: [],
            momentumPhase: .ended
        )
        let nextDirectBegin = gesture.beginsZoom(
            phase: .began,
            momentumPhase: []
        )

        #expect(directBegin)
        #expect(!directChange)
        #expect(!directEnd)
        #expect(!momentumBegin)
        #expect(!momentumChange)
        #expect(!momentumEnd)
        #expect(nextDirectBegin)
    }

    @Test
    func treatsPhaseLessMouseWheelEventsAsSeparateGestures() {
        var gesture = ImageSurfaceScrollGesture()

        let first = gesture.beginsZoom(phase: [], momentumPhase: [])
        let second = gesture.beginsZoom(phase: [], momentumPhase: [])

        #expect(first)
        #expect(second)
    }

    @Test
    func doesNotRestartAnchorBetweenMayBeginAndBegin() {
        var gesture = ImageSurfaceScrollGesture()

        let mayBegin = gesture.beginsZoom(
            phase: .mayBegin,
            momentumPhase: []
        )
        let begin = gesture.beginsZoom(
            phase: .began,
            momentumPhase: []
        )

        #expect(mayBegin)
        #expect(!begin)
    }

}
