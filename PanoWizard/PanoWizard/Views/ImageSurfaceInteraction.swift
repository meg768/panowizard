import AppKit

enum MaskOverlayAppearance {
    static let committedOpacity = 0.55
    static let activeStrokeOpacity = 0.8
}

enum ImageSurfaceInteraction: Equatable, Sendable {
    case navigate
    case edit
    case remove

    init(modifierFlags: NSEvent.ModifierFlags) {
        guard modifierFlags.contains(.option) else {
            self = .navigate
            return
        }
        self = modifierFlags.contains(.command) ? .remove : .edit
    }
}

enum ImageSurfaceScrollIntent: Equatable, Sendable {
    case pan(horizontal: CGFloat, vertical: CGFloat)
    case zoom(CGFloat)
    case ignore
}

enum ImageSurfaceScroll {
    static func intent(
        horizontal: CGFloat,
        vertical: CGFloat,
        isDirectionInverted: Bool,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ImageSurfaceScrollIntent {
        guard modifierFlags.contains(.command) else {
            return .pan(horizontal: horizontal, vertical: vertical)
        }
        guard abs(vertical) >= abs(horizontal), abs(vertical) > 0.01 else {
            return .ignore
        }
        return .zoom(isDirectionInverted ? -vertical : vertical)
    }

    static func intent(for event: NSEvent) -> ImageSurfaceScrollIntent {
        intent(
            horizontal: event.scrollingDeltaX,
            vertical: event.scrollingDeltaY,
            isDirectionInverted: event.isDirectionInvertedFromDevice,
            modifierFlags: event.modifierFlags
        )
    }
}

struct ImageSurfaceScrollGesture {
    private enum State {
        case inactive
        case direct
        case awaitingMomentum
        case momentum
    }

    private var state = State.inactive

    mutating func beginsZoom(
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase
    ) -> Bool {
        // Traditional mouse wheels do not expose gesture phases, so each
        // phase-less event is its own gesture. Trackpads retain one anchor
        // from the direct phase through its momentum phase.
        guard !phase.isEmpty || !momentumPhase.isEmpty else {
            state = .inactive
            return true
        }

        if momentumPhase.contains(.ended)
            || momentumPhase.contains(.cancelled) {
            state = .inactive
            return false
        }
        if momentumPhase.contains(.began)
            || momentumPhase.contains(.changed) {
            let begins = state == .inactive
            state = .momentum
            return begins
        }
        if phase.contains(.cancelled) {
            state = .inactive
            return false
        }
        if phase.contains(.mayBegin)
            || phase.contains(.began)
            || phase.contains(.changed) {
            let begins = state != .direct
            state = .direct
            return begins
        }
        if phase.contains(.ended) {
            let begins = state == .inactive
            state = .awaitingMomentum
            return begins
        }
        return state == .inactive
    }

    mutating func reset() {
        state = .inactive
    }
}

@MainActor
@objc protocol ImageNavigationResponder: AnyObject {
    func zoomImageIn(_ sender: Any?)
    func zoomImageOut(_ sender: Any?)
    func resetImageView(_ sender: Any?)
}

@MainActor
enum ImageNavigationCommands {
    static func send(_ action: Selector) {
        if NSApp.sendAction(action, to: nil, from: nil) { return }
        guard let root = NSApp.keyWindow?.contentView,
              let target = navigationView(in: root) else { return }
        NSApp.sendAction(action, to: target, from: nil)
    }

    private static func navigationView(in view: NSView) -> NSView? {
        guard !view.isHidden else { return nil }
        if view is ImageNavigationResponder { return view }
        return view.subviews.lazy.compactMap { navigationView(in: $0) }.first
    }
}
