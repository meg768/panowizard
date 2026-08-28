import AppKit

enum ImageSurfaceInteraction: Equatable, Sendable {
    case navigate
    case edit
    case remove

    init(modifierFlags: NSEvent.ModifierFlags) {
        guard modifierFlags.contains(.command) else {
            self = .navigate
            return
        }
        self = modifierFlags.contains(.option) ? .remove : .edit
    }
}

enum ImageSurfaceScroll {
    static func dominantDelta(
        horizontal: CGFloat,
        vertical: CGFloat,
        isDirectionInverted: Bool
    ) -> CGFloat {
        let delta = abs(vertical) >= abs(horizontal) ? vertical : horizontal
        return isDirectionInverted ? -delta : delta
    }

    static func dominantDelta(for event: NSEvent) -> CGFloat {
        dominantDelta(
            horizontal: event.scrollingDeltaX,
            vertical: event.scrollingDeltaY,
            isDirectionInverted: event.isDirectionInvertedFromDevice
        )
    }
}
