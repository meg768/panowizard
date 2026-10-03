import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum LittlePlanetPanoramaDragMode: Equatable {
    case pan
    case center

    init(modifierFlags: NSEvent.ModifierFlags) {
        self = modifierFlags.contains(.option) ? .center : .pan
    }
}

struct LittlePlanetPanoramaSelection {
    static func clampedLocation(
        _ location: CGPoint,
        in size: CGSize
    ) -> CGPoint {
        CGPoint(
            x: min(max(location.x, 0), size.width),
            y: min(max(location.y, 0), size.height)
        )
    }

    static func sourceCoordinates(
        at location: CGPoint,
        viewportSize: CGSize,
        panoramaWidth: CGFloat,
        panTurns: Double
    ) -> (longitudeDegrees: Double, latitudeDegrees: Double) {
        let sourceX = wrappedUnit(
            Double((location.x - viewportSize.width / 2) / panoramaWidth)
                - panTurns
        )
        let sourceY = min(max(
            1.0 - Double(location.y / viewportSize.height),
            0.0
        ), 1.0)
        return (sourceX * 360, (sourceY - 0.5) * 180)
    }

    private static func wrappedUnit(_ value: Double) -> Double {
        value - floor(value)
    }
}

@MainActor
@Observable
final class LittlePlanetExportController {
    static let previewSide = 640

    var settings = LittlePlanetSettings()
    var panoramaImage: NSImage?
    var previewImage: NSImage?
    var errorMessage: String?
    var isLoading = true
    var isSaving = false

    private var source: LittlePlanetSource?
    private var previewTask: Task<Void, Never>?

    func load(
        sourceURL: URL,
        adjustments: PanoramaAdjustments
    ) {
        guard source == nil else { return }
        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    let source = try LittlePlanetSource(
                        panoramaURL: sourceURL,
                        adjustments: adjustments
                    )
                    return (source, try source.makeImage())
                }.value
                source = loaded.0
                panoramaImage = NSImage(cgImage: loaded.1, size: .zero)
                isLoading = false
                renderPreview()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func save(
        directoryURL: URL?,
        onSuccess: @escaping () -> Void
    ) {
        guard let source else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = directoryURL
        panel.nameFieldStringValue = "little-planet.png"
        panel.title = "Export Little Planet"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let settings = settings
        isSaving = true
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let image = try LittlePlanetRenderer.render(
                        source: source,
                        side: source.height,
                        settings: settings
                    )
                    try LittlePlanetRenderer.writePNG(image, to: url)
                }.value
                isSaving = false
                onSuccess()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    func renderPreview() {
        previewTask?.cancel()
        guard let source else { return }
        let settings = settings
        let previewSide = Self.previewSide
        previewTask = Task {
            do {
                let rendering = Task.detached(priority: .userInitiated) {
                    try LittlePlanetRenderer.render(
                        source: source,
                        side: previewSide,
                        settings: settings
                    )
                }
                let image = try await withTaskCancellationHandler {
                    try await rendering.value
                } onCancel: {
                    rendering.cancel()
                }
                guard !Task.isCancelled else { return }
                previewImage = NSImage(cgImage: image, size: .zero)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct LittlePlanetExportSheet: View {
    let panoramaURL: URL
    let adjustments: PanoramaAdjustments
    let projectDirectoryURL: URL?
    let onDismiss: () -> Void

    @State private var controller = LittlePlanetExportController()
    @State private var panoramaPanTurns = 0.0
    @State private var panoramaDragTranslation: CGFloat = 0
    @State private var panoramaScrollTranslation: CGFloat = 0
    @State private var panoramaDragMode: LittlePlanetPanoramaDragMode?
    @State private var pendingCenterLocation: CGPoint?

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create Little Planet")
                    .font(.title2.bold())
                Text("Turn your 360° panorama into a Little Planet projection.")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                littlePlanetPane(
                    title: "Panorama",
                    content: panoramaPicker
                ) {
                    Text("Drag to rotate · ⌥-drag to center")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 44,
                            alignment: .topLeading
                        )
                }

                littlePlanetPane(
                    title: "Little Planet",
                    content: planetPreview
                ) {
                    VStack(spacing: 2) {
                        Slider(
                            value: $controller.settings.horizonPercent,
                            in: 10...75,
                            onEditingChanged: { isEditing in
                                if !isEditing { controller.renderPreview() }
                            }
                        )
                        .frame(width: 260, height: 24)
                        .disabled(controller.isLoading || controller.isSaving)

                        Text("Slide to resize")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
                }
            }

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Export…") {
                    controller.save(
                        directoryURL: projectDirectoryURL,
                        onSuccess: onDismiss
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    controller.previewImage == nil
                        || controller.isLoading
                        || controller.isSaving
                )
            }
        }
        .padding(22)
        .frame(width: 780)
        .task {
            controller.load(
                sourceURL: panoramaURL,
                adjustments: adjustments
            )
        }
        .alert("Little Planet Failed", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? "Unknown error")
        }
    }

    private var panoramaPicker: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, 1)
            let panoramaWidth = height * 2
            let manipulationTranslation = panoramaDragTranslation
                + panoramaScrollTranslation
            let manipulationTurns = Double(
                manipulationTranslation / panoramaWidth
            )
            let displayedPanTurns = panoramaPanTurns + manipulationTurns
            let viewportCenterTurns = Double(width / 2 / panoramaWidth)
            let imageOriginX = CGFloat(
                wrappedUnit(viewportCenterTurns + displayedPanTurns)
            ) * panoramaWidth
            let centerLongitude = wrappedUnit(
                controller.settings.centerLongitudeDegrees / 360.0
            )
            let markerX = CGFloat(wrappedUnit(
                viewportCenterTurns + displayedPanTurns + centerLongitude
            )) * panoramaWidth
            let markerY = CGFloat(min(max(
                0.5 - controller.settings.centerLatitudeDegrees / 180.0,
                0.0
            ), 1.0)) * height

            ZStack(alignment: .topLeading) {
                if let image = controller.panoramaImage {
                    ForEach(-1...1, id: \.self) { copy in
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: panoramaWidth, height: height)
                            .scaleEffect(y: -1)
                            .position(
                                x: imageOriginX
                                    + CGFloat(copy) * panoramaWidth
                                    + panoramaWidth / 2,
                                y: height / 2
                            )
                    }
                    if let pendingCenterLocation {
                        centerMarker
                            .position(pendingCenterLocation)
                    } else {
                        ForEach(-1...1, id: \.self) { copy in
                            centerMarker
                                .position(
                                    x: markerX + CGFloat(copy) * panoramaWidth,
                                    y: markerY
                                )
                        }
                    }
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .frame(width: width, height: height)
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let mode = panoramaDragMode
                            ?? LittlePlanetPanoramaDragMode(
                                modifierFlags: NSEvent.modifierFlags
                            )
                        panoramaDragMode = mode
                        switch mode {
                        case .pan:
                            panoramaDragTranslation = value.translation.width
                        case .center:
                            pendingCenterLocation = LittlePlanetPanoramaSelection
                                .clampedLocation(
                                    value.location,
                                    in: geometry.size
                                )
                        }
                    }
                    .onEnded { value in
                        let mode = panoramaDragMode
                            ?? LittlePlanetPanoramaDragMode(
                                modifierFlags: NSEvent.modifierFlags
                            )
                        panoramaDragMode = nil
                        switch mode {
                        case .pan:
                            panoramaDragTranslation = 0
                            completePan(
                                translation: value.translation.width,
                                panoramaWidth: panoramaWidth
                            )
                        case .center:
                            let location = pendingCenterLocation
                                ?? LittlePlanetPanoramaSelection.clampedLocation(
                                    value.location,
                                    in: geometry.size
                                )
                            pendingCenterLocation = nil
                            commitCenter(
                                at: location,
                                viewportSize: geometry.size,
                                panoramaWidth: panoramaWidth,
                                panTurns: displayedPanTurns
                            )
                        }
                    }
            )
            .background {
                LittlePlanetHorizontalScrollMonitor(
                    isEnabled: !controller.isLoading && !controller.isSaving,
                    onChange: { translation in
                        panoramaScrollTranslation = translation
                    },
                    onEnd: { translation in
                        panoramaScrollTranslation = 0
                        completePan(
                            translation: translation,
                            panoramaWidth: panoramaWidth
                        )
                    }
                )
            }
            .allowsHitTesting(!controller.isLoading && !controller.isSaving)
        }
    }

    private var centerMarker: some View {
        Circle()
            .fill(Color.accentColor)
            .stroke(.white.opacity(0.9), lineWidth: 1)
            .frame(width: 10, height: 10)
    }

    private func littlePlanetPane<Content: View, Footer: View>(
        title: String,
        content: Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .frame(height: 24)

            content
                .frame(width: 360, height: 360)
                .background(
                    .black.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            footer()
        }
        .frame(width: 360)
    }

    @ViewBuilder
    private var planetPreview: some View {
        if let image = controller.previewImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            ProgressView()
                .controlSize(.large)
        }
    }

    private func wrappedUnit(_ value: Double) -> Double {
        value - floor(value)
    }

    private func wrappedTurn(_ value: Double) -> Double {
        value - floor(value + 0.5)
    }

    private func completePan(
        translation: CGFloat,
        panoramaWidth: CGFloat
    ) {
        guard panoramaWidth > 0, abs(translation) > 0.01 else { return }
        let finalTurns = wrappedTurn(
            panoramaPanTurns + Double(translation / panoramaWidth)
        )
        panoramaPanTurns = finalTurns
        controller.settings.rotationDegrees = rotationDegrees(
            forPanTurns: finalTurns
        )
        controller.renderPreview()
    }

    private func commitCenter(
        at location: CGPoint,
        viewportSize: CGSize,
        panoramaWidth: CGFloat,
        panTurns: Double
    ) {
        let coordinates = LittlePlanetPanoramaSelection.sourceCoordinates(
            at: location,
            viewportSize: viewportSize,
            panoramaWidth: panoramaWidth,
            panTurns: panTurns
        )
        controller.settings.centerLongitudeDegrees = coordinates.longitudeDegrees
        controller.settings.centerLatitudeDegrees = coordinates.latitudeDegrees
        controller.settings.rotationDegrees = rotationDegrees(
            forPanTurns: panTurns
        )
        controller.renderPreview()
    }

    private func rotationDegrees(forPanTurns panTurns: Double) -> Double {
        LittlePlanetProjection.rotationDegrees(
            placingSourceLongitudeAtTop: -panTurns * 360,
            centerLongitudeDegrees: controller.settings.centerLongitudeDegrees,
            centerLatitudeDegrees: controller.settings.centerLatitudeDegrees
        )
    }

}

private struct LittlePlanetHorizontalScrollMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onEnd: onEnd)
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        context.coordinator.view = view
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
    }

    static func dismantleNSView(
        _ view: AttachmentView,
        coordinator: Coordinator
    ) {
        coordinator.uninstall()
    }

    final class AttachmentView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        weak var view: AttachmentView?
        var isEnabled = true
        var onChange: (CGFloat) -> Void
        var onEnd: (CGFloat) -> Void

        private var monitor: Any?
        private var accumulatedDelta: CGFloat = 0
        private var isDirectScroll = false
        private var ignoresMomentum = false

        init(
            onChange: @escaping (CGFloat) -> Void,
            onEnd: @escaping (CGFloat) -> Void
        ) {
            self.onChange = onChange
            self.onEnd = onEnd
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled,
                  let view,
                  let window = view.window,
                  event.window === window,
                  view.bounds.contains(view.convert(
                      event.locationInWindow,
                      from: nil
                  )) else { return event }

            if !event.momentumPhase.isEmpty {
                guard ignoresMomentum else { return event }
                if event.momentumPhase.contains(.ended)
                    || event.momentumPhase.contains(.cancelled) {
                    ignoresMomentum = false
                }
                return nil
            }

            let horizontal = event.scrollingDeltaX
            let isHorizontal = abs(horizontal) > 0.01
                && abs(horizontal) >= abs(event.scrollingDeltaY)

            if event.phase.isEmpty {
                guard isHorizontal else { return event }
                ignoresMomentum = false
                onChange(horizontal)
                onEnd(horizontal)
                return nil
            }

            if event.phase.contains(.began)
                || event.phase.contains(.mayBegin) {
                ignoresMomentum = false
                guard isHorizontal else { return event }
                accumulatedDelta = horizontal
                isDirectScroll = true
                onChange(accumulatedDelta)
                return nil
            }

            if event.phase.contains(.changed) {
                if !isDirectScroll {
                    guard isHorizontal else { return event }
                    accumulatedDelta = 0
                    isDirectScroll = true
                }
                accumulatedDelta += horizontal
                onChange(accumulatedDelta)
                return nil
            }

            if event.phase.contains(.ended)
                || event.phase.contains(.cancelled) {
                guard isDirectScroll else { return event }
                accumulatedDelta += horizontal
                let completedDelta = accumulatedDelta
                accumulatedDelta = 0
                isDirectScroll = false
                ignoresMomentum = true
                onEnd(completedDelta)
                return nil
            }

            return event
        }
    }
}
