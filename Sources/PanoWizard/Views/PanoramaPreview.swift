@preconcurrency import AppKit
import ImageIO
import SwiftUI

struct PanoramaPreview: View {
    let panorama: PanoramaSet?
    let imageURL: URL?
    let isStitched: Bool
    let nadirOverlayURL: URL?
    let zenithOverlayURL: URL?
    let nadirRetouchURL: URL?
    let zenithRetouchURL: URL?
    let selectedSource: SourceImage?
    let maskData: Data?
    let protectedMaskData: Data?
    let maskTool: SourceMaskTool
    let maskIntent: AppModel.SourceMaskIntent
    let initialViewpoint: PanoramaViewpoint
    let onViewpointChange: (PanoramaViewpoint) -> Void
    let onMasksChange: (Data?, Data?) -> Void

    @State private var sourceViewports: [SourceImage.ID: SourceViewport] = [:]

    var body: some View {
        Group {
            if let panorama {
                if isStitched, let imageURL {
                    SphericalPanoramaView(
                        url: imageURL,
                        overlayURL: nadirOverlayURL,
                        zenithOverlayURL: zenithOverlayURL,
                        nadirRetouchURL: nadirRetouchURL,
                        zenithRetouchURL: zenithRetouchURL,
                        initialViewpoint: initialViewpoint,
                        onViewpointChange: onViewpointChange
                    )
                } else if let selectedSource {
                    SourceMaskEditor(
                        image: selectedSource,
                        maskData: maskData,
                        protectedMaskData: protectedMaskData,
                        maskTool: maskTool,
                        maskIntent: maskIntent,
                        viewport: sourceViewport(for: selectedSource.id),
                        onMasksChange: onMasksChange
                    )
                } else if let imageURL {
                    VStack(spacing: 12) {
                        ZoomableImageView(url: imageURL)
                        Text("\(panorama.images.count) källbilder väntar på sammanfogning")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Inget panorama skapat", systemImage: "panorama")
                    } description: {
                        Text(
                            "Skapa panoramat för att förhandsvisa det i 360°."
                        )
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Dra in dina bilder", systemImage: "photo.badge.plus")
                } description: {
                    Text("Släpp en mapp eller flera överlappande bilder här.")
                } actions: {
                    Text("PanoWizard läser metadata och ordnar bilderna automatiskt.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func sourceViewport(
        for imageID: SourceImage.ID
    ) -> Binding<SourceViewport> {
        Binding(
            get: { sourceViewports[imageID] ?? SourceViewport() },
            set: { sourceViewports[imageID] = $0 }
        )
    }
}

private struct SourceViewport: Equatable {
    var zoom = 1.0
    var center = UnitPoint.center
}

private struct SourceMaskEditor: View {
    let image: SourceImage
    let maskData: Data?
    let protectedMaskData: Data?
    let maskTool: SourceMaskTool
    let maskIntent: AppModel.SourceMaskIntent
    @Binding var viewport: SourceViewport
    let onMasksChange: (Data?, Data?) -> Void

    @State private var sourceImage: CGImage?
    @State private var maskImage: CGImage?
    @State private var protectedMaskImage: CGImage?
    @State private var activeStroke: [MaskPoint] = []
    @State private var circleStart: MaskPoint?
    @State private var circleEnd: MaskPoint?
    @State private var zoomAnchor = UnitPoint.center
    @State private var pendingZoomAnchor: UnitPoint?
    @State private var hoverPoint: CGPoint?
    @State private var isSystemCursorHidden = false
    @State private var magnificationStartZoom: Double?
    @State private var scrollPosition = ScrollPosition()
    @State private var pendingViewportCenter: UnitPoint?
    @State private var pointerGesture: PointerGesture?
    @State private var modifierInteraction = ImageSurfaceInteraction.navigate
    @State private var lastHoverPoint: CGPoint?
    @State private var activeGestureErases = false

    private let zoomAnchorID = "source-image-zoom-anchor"
    /// Brush size in screen points. Zoom changes how many source pixels those
    /// points cover, not the apparent size of the brush cursor.
    private let screenBrushDiameter: CGFloat = 48

    private enum PointerGesture {
        case edit
    }

    private var zoom: Double { viewport.zoom }

    var body: some View {
        GeometryReader { geometry in
            if let sourceImage {
                let imageSize = CGSize(
                    width: sourceImage.width,
                    height: sourceImage.height
                )
                let fitSize = aspectFitSize(
                    contentSize: imageSize,
                    containerSize: geometry.size,
                    padding: 40
                )
                let displaySize = CGSize(
                    width: fitSize.width * zoom,
                    height: fitSize.height * zoom
                )
                let displayScale = displaySize.width / imageSize.width
                let displayedBrushRadius = screenBrushDiameter / 2

                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            Image(decorative: sourceImage, scale: 1)
                                .resizable()
                                .frame(width: displaySize.width, height: displaySize.height)
                                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

                            if let maskImage {
                                Image(decorative: maskImage, scale: 1)
                                    .resizable()
                                    .frame(
                                        width: displaySize.width,
                                        height: displaySize.height
                                    )
                                    .opacity(0.55)
                                    .allowsHitTesting(false)
                            }

                            if let protectedMaskImage {
                                Image(decorative: protectedMaskImage, scale: 1)
                                    .resizable()
                                    .frame(
                                        width: displaySize.width,
                                        height: displaySize.height
                                    )
                                    .opacity(0.55)
                                    .allowsHitTesting(false)
                            }

                            Canvas { context, _ in
                                if let circleStart, let circleEnd,
                                   maskTool == .rectangle {
                                    let center = CGPoint(
                                        x: circleStart.x * displaySize.width,
                                        y: circleStart.y * displaySize.height
                                    )
                                    let edge = CGPoint(
                                        x: circleEnd.x * displaySize.width,
                                        y: circleEnd.y * displaySize.height
                                    )
                                    let rect = CGRect(
                                        x: min(center.x, edge.x),
                                        y: min(center.y, edge.y),
                                        width: abs(edge.x - center.x),
                                        height: abs(edge.y - center.y)
                                    )
                                    let color = strokeColor
                                    let shape = Path(rect)
                                    if previewIsErasing {
                                        context.clip(to: shape)
                                        context.draw(
                                            Image(decorative: sourceImage, scale: 1),
                                            in: CGRect(origin: .zero, size: displaySize)
                                        )
                                    } else {
                                        context.fill(
                                            shape,
                                            with: .color(color.opacity(0.28))
                                        )
                                    }
                                    context.stroke(
                                        shape,
                                        with: .color(.black.opacity(0.85)),
                                        lineWidth: 3
                                    )
                                    context.stroke(
                                        shape,
                                        with: .color(.white),
                                        lineWidth: 1
                                    )
                                    return
                                }
                                guard !activeStroke.isEmpty else { return }
                                let points = activeStroke.map {
                                    CGPoint(
                                        x: $0.x * displaySize.width,
                                        y: $0.y * displaySize.height
                                    )
                                }
                                var path = Path()
                                path.move(to: points[0])
                                points.dropFirst().forEach { path.addLine(to: $0) }
                                let style = StrokeStyle(
                                    lineWidth: max(displayedBrushRadius * 2, 1),
                                    lineCap: .round, lineJoin: .round
                                )
                                if previewIsErasing {
                                    context.clip(to: path.strokedPath(style))
                                    context.draw(
                                        Image(decorative: sourceImage, scale: 1),
                                        in: CGRect(origin: .zero, size: displaySize)
                                    )
                                } else {
                                    context.stroke(
                                        path,
                                        with: .color(strokeColor.opacity(0.8)),
                                        style: style
                                    )
                                }
                            }
                            .allowsHitTesting(false)

                            Canvas { context, _ in
                                guard let hoverPoint else { return }
                                if maskTool == .rectangle {
                                    let arm: CGFloat = 8
                                    var crosshair = Path()
                                    crosshair.move(to: CGPoint(x: hoverPoint.x - arm, y: hoverPoint.y))
                                    crosshair.addLine(to: CGPoint(x: hoverPoint.x + arm, y: hoverPoint.y))
                                    crosshair.move(to: CGPoint(x: hoverPoint.x, y: hoverPoint.y - arm))
                                    crosshair.addLine(to: CGPoint(x: hoverPoint.x, y: hoverPoint.y + arm))
                                    context.stroke(crosshair, with: .color(.black), lineWidth: 3)
                                    context.stroke(crosshair, with: .color(.white), lineWidth: 1)
                                    if previewIsErasing {
                                        drawEraseIndicator(
                                            in: context,
                                            center: hoverPoint,
                                            radius: 10
                                        )
                                    }
                                    return
                                }
                                let diameter = max(displayedBrushRadius * 2, 1)
                                let cursorRect = CGRect(
                                    x: hoverPoint.x - displayedBrushRadius,
                                    y: hoverPoint.y - displayedBrushRadius,
                                    width: diameter,
                                    height: diameter
                                )
                                context.stroke(
                                    Path(ellipseIn: cursorRect),
                                    with: .color(.black.opacity(0.8)),
                                    lineWidth: 3
                                )
                                context.stroke(
                                    Path(ellipseIn: cursorRect),
                                    with: .color(.white),
                                    lineWidth: 1
                                )
                                let centerSize: CGFloat = 3
                                context.fill(
                                    Path(ellipseIn: CGRect(
                                        x: hoverPoint.x - centerSize / 2,
                                        y: hoverPoint.y - centerSize / 2,
                                        width: centerSize,
                                        height: centerSize
                                    )),
                                    with: .color(.white)
                                )
                                if previewIsErasing {
                                    drawEraseIndicator(
                                        in: context,
                                        center: hoverPoint,
                                        radius: displayedBrushRadius * 0.7
                                    )
                                }
                            }
                            .allowsHitTesting(false)

                            Color.clear
                                .frame(width: 1, height: 1)
                                .position(
                                    x: zoomAnchor.x * displaySize.width,
                                    y: zoomAnchor.y * displaySize.height
                                )
                                .id(zoomAnchorID)
                        }
                        .frame(width: displaySize.width, height: displaySize.height)
                        .background {
                            NativeImagePanMonitor()
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if pointerGesture == nil {
                                        let interaction = ImageSurfaceInteraction(
                                            modifierFlags: NSEvent.modifierFlags
                                        )
                                        modifierInteraction = interaction
                                        switch interaction {
                                        case .navigate:
                                            return
                                        case .edit, .remove:
                                            pointerGesture = .edit
                                            activeGestureErases =
                                                interaction == .remove
                                        }
                                    }
                                    guard case .edit = pointerGesture else { return }
                                    hoverPoint = value.location
                                    let point = MaskPoint(
                                        x: value.location.x / displaySize.width,
                                        y: value.location.y / displaySize.height
                                    )
                                    if maskTool == .rectangle {
                                        if circleStart == nil {
                                            circleStart = point
                                        }
                                        circleEnd = point
                                    } else if activeStroke.last != point {
                                        activeStroke.append(point)
                                    }
                                }
                                .onEnded { _ in
                                    if case .edit = pointerGesture {
                                        if maskTool == .rectangle {
                                            commitShape(sourceImage: sourceImage)
                                        } else {
                                            commitStroke(
                                                sourceImage: sourceImage,
                                                displayScale: displayScale
                                            )
                                        }
                                    }
                                    pointerGesture = nil
                                    activeGestureErases = false
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                modifierInteraction = ImageSurfaceInteraction(
                                    modifierFlags: NSEvent.modifierFlags
                                )
                                lastHoverPoint = location
                                updateCursorFeedback()
                            case .ended:
                                lastHoverPoint = nil
                                hoverPoint = nil
                                showSystemCursor()
                            }
                        }
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height
                        )
                    }
                    .scrollIndicators(.visible)
                    .scrollDisabled(
                        modifierInteraction != .navigate
                            || pointerGesture != nil
                    )
                    .scrollPosition($scrollPosition)
                    .onScrollGeometryChange(for: ScrollGeometry.self) { geometry in
                        geometry
                    } action: { _, geometry in
                        updateViewport(using: geometry)
                    }
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let start = magnificationStartZoom ?? zoom
                                if magnificationStartZoom == nil {
                                    magnificationStartZoom = zoom
                                }
                                setZoom(start * value.magnification)
                            }
                            .onEnded { _ in
                                magnificationStartZoom = nil
                            }
                    )
                    .onChange(of: zoom) {
                        guard let anchor = pendingZoomAnchor else { return }
                        pendingZoomAnchor = nil
                        proxy.scrollTo(zoomAnchorID, anchor: anchor)
                    }
                }
            } else {
                ContentUnavailableView("Bilden kunde inte läsas", systemImage: "photo")
            }
        }
        .background(.background)
        .background {
            ZStack {
                ScrollWheelZoomMonitor { delta, anchor in
                    zoomAnchor = anchor
                    pendingZoomAnchor = anchor
                    setZoom(zoom * exp(-delta * 0.01))
                }
                ImageSurfaceModifierMonitor { interaction in
                    modifierInteraction = interaction
                    updateCursorFeedback()
                }
            }
        }
        .task(id: image.id) {
            pendingViewportCenter = viewport.center
            sourceImage = Self.loadImage(at: image.url)
            maskImage = Self.loadImage(data: maskData)
            protectedMaskImage = Self.loadImage(data: protectedMaskData)
            activeStroke = []
            circleStart = nil
            circleEnd = nil
            pointerGesture = nil
            activeGestureErases = false
        }
        .onChange(of: maskData) {
            maskImage = Self.loadImage(data: maskData)
        }
        .onChange(of: protectedMaskData) {
            protectedMaskImage = Self.loadImage(data: protectedMaskData)
        }
        .onChange(of: maskTool) {
            activeStroke = []
            circleStart = nil
            circleEnd = nil
            updateCursorFeedback()
        }
        .onDisappear {
            showSystemCursor()
        }
    }

    private func setZoom(_ zoom: Double) {
        viewport.zoom = min(max(zoom, 1), 8)
    }

    private func updateViewport(using geometry: ScrollGeometry) {
        guard geometry.contentSize.width > 0,
              geometry.contentSize.height > 0 else { return }
        if let center = pendingViewportCenter {
            pendingViewportCenter = nil
            scrollPosition.scrollTo(
                x: max(
                    center.x * geometry.contentSize.width
                        - geometry.containerSize.width / 2,
                    0
                ),
                y: max(
                    center.y * geometry.contentSize.height
                        - geometry.containerSize.height / 2,
                    0
                )
            )
            return
        }
        let center = UnitPoint(
            x: min(max(
                geometry.visibleRect.midX / geometry.contentSize.width,
                0
            ), 1),
            y: min(max(
                geometry.visibleRect.midY / geometry.contentSize.height,
                0
            ), 1)
        )
        guard center != viewport.center else { return }
        viewport.center = center
    }

    private var previewIsErasing: Bool {
        activeGestureErases
            || modifierInteraction == .remove
            || maskIntent == .erase
    }

    private var strokeColor: Color {
        if previewIsErasing { return .white }
        switch maskIntent {
        case .exclude: return .red
        case .protect: return .green
        case .erase: return .white
        }
    }

    private func commitStroke(
        sourceImage: CGImage,
        displayScale: CGFloat
    ) {
        guard !activeStroke.isEmpty, displayScale > 0 else { return }
        let radius = screenBrushDiameter / 2 / displayScale
        let apply: (Data?, Bool, AppModel.SourceMaskIntent) -> Data? = { data, erase, intent in
            SourceMaskRasterizer.applying(
                stroke: activeStroke, radius: radius, erasing: erase,
                protectedArea: intent == .protect, to: data,
                width: sourceImage.width, height: sourceImage.height
            )
        }
        applyToAllMasks(
            erasing: activeGestureErases || maskIntent == .erase,
            apply: apply
        )
        activeStroke = []
    }

    private func commitShape(sourceImage: CGImage) {
        guard let start = circleStart, let end = circleEnd else { return }
        let deltaX = (end.x - start.x) * CGFloat(sourceImage.width)
        let deltaY = (end.y - start.y) * CGFloat(sourceImage.height)
        let radius = hypot(deltaX, deltaY)
        circleStart = nil
        circleEnd = nil
        guard radius >= 1 else { return }
        let apply: (Data?, Bool, AppModel.SourceMaskIntent) -> Data? = { data, erase, intent in
            if maskTool == .rectangle {
                return SourceMaskRasterizer.applyingRectangle(
                    from: start, to: end, erasing: erase,
                    protectedArea: intent == .protect, to: data,
                    width: sourceImage.width, height: sourceImage.height
                )
            }
            return SourceMaskRasterizer.applyingCircle(
                center: start, radius: radius, erasing: erase,
                protectedArea: intent == .protect, to: data,
                width: sourceImage.width, height: sourceImage.height
            )
        }
        applyToAllMasks(
            erasing: activeGestureErases || maskIntent == .erase,
            apply: apply
        )
    }

    private func applyToAllMasks(
        erasing: Bool,
        apply: (Data?, Bool, AppModel.SourceMaskIntent) -> Data?
    ) {
        let eraseAll = erasing
        let red = apply(maskData, eraseAll || maskIntent != .exclude, .exclude)
        let green = apply(
            protectedMaskData, eraseAll || maskIntent != .protect, .protect
        )
        onMasksChange(red, green)
    }

    private func hideSystemCursor() {
        guard !isSystemCursorHidden else { return }
        NSCursor.hide()
        isSystemCursorHidden = true
    }

    private func showSystemCursor() {
        guard isSystemCursorHidden else { return }
        NSCursor.unhide()
        isSystemCursorHidden = false
    }

    private func updateCursorFeedback() {
        guard let lastHoverPoint else { return }
        if modifierInteraction == .navigate {
            hoverPoint = nil
            showSystemCursor()
            NSCursor.openHand.set()
        } else {
            hoverPoint = lastHoverPoint
            hideSystemCursor()
        }
    }

    private func drawEraseIndicator(
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat
    ) {
        var slash = Path()
        slash.move(to: CGPoint(x: center.x - radius, y: center.y - radius))
        slash.addLine(to: CGPoint(x: center.x + radius, y: center.y + radius))
        context.stroke(slash, with: .color(.black.opacity(0.85)), lineWidth: 3)
        context.stroke(slash, with: .color(.white), lineWidth: 1)
    }

    private func aspectFitSize(
        contentSize: CGSize,
        containerSize: CGSize,
        padding: CGFloat
    ) -> CGSize {
        let available = CGSize(
            width: max(containerSize.width - padding * 2, 1),
            height: max(containerSize.height - padding * 2, 1)
        )
        let scale = min(
            available.width / contentSize.width,
            available.height / contentSize.height
        )
        return CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
    }

    private static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 12_000
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func loadImage(data: Data?) -> CGImage? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

private struct ScrollWheelZoomMonitor: NSViewRepresentable {
    let onScroll: (Double, UnitPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.windowNumber = view.window?.windowNumber
        context.coordinator.hitRectInWindow = view.convert(view.bounds, to: nil)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onScroll: (Double, UnitPoint) -> Void
        private weak var view: NSView?
        private var monitor: Any?
        var windowNumber: Int?
        var hitRectInWindow = CGRect.zero

        init(onScroll: @escaping (Double, UnitPoint) -> Void) {
            self.onScroll = onScroll
        }

        func install(for view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self,
                      self.windowNumber == event.windowNumber,
                      self.hitRectInWindow.contains(event.locationInWindow)
                else { return event }
                let physicalDelta = ImageSurfaceScroll.dominantDelta(for: event)
                let anchor = UnitPoint(
                    x: min(max(
                        (event.locationInWindow.x - self.hitRectInWindow.minX)
                            / max(self.hitRectInWindow.width, 1), 0
                    ), 1),
                    y: min(max(
                        1 - (event.locationInWindow.y - self.hitRectInWindow.minY)
                            / max(self.hitRectInWindow.height, 1), 0
                    ), 1)
                )
                guard abs(physicalDelta) > 0.01 else { return nil }
                self.onScroll(physicalDelta, anchor)
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { uninstall() }
    }
}

private struct ImageSurfaceModifierMonitor: NSViewRepresentable {
    let onChange: (ImageSurfaceInteraction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.windowNumber = view.window?.windowNumber
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onChange: (ImageSurfaceInteraction) -> Void
        var windowNumber: Int?
        private var monitor: Any?

        init(onChange: @escaping (ImageSurfaceInteraction) -> Void) {
            self.onChange = onChange
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: .flagsChanged
            ) { [weak self] event in
                guard let self,
                      event.windowNumber == 0
                        || self.windowNumber == event.windowNumber else {
                    return event
                }
                self.onChange(ImageSurfaceInteraction(
                    modifierFlags: event.modifierFlags
                ))
                return event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { uninstall() }
    }
}

private struct NativeImagePanMonitor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onHierarchyChange = { [weak coordinator = context.coordinator,
                                    weak view] in
            guard let coordinator, let view else { return }
            coordinator.scrollView = view.enclosingScrollView
        }
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        context.coordinator.scrollView = view.enclosingScrollView
    }

    static func dismantleNSView(
        _ view: AttachmentView,
        coordinator: Coordinator
    ) {
        coordinator.uninstall()
    }

    final class AttachmentView: NSView {
        var onHierarchyChange: (() -> Void)?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            onHierarchyChange?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onHierarchyChange?()
        }
    }

    @MainActor
    final class Coordinator {
        weak var scrollView: NSScrollView?
        private var monitor: Any?
        private var panOrigin: CGPoint?
        private var panStart: CGPoint?
        private var pushedCursor = false

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            finishPan()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.type == .leftMouseUp, panOrigin != nil {
                finishPan()
                return nil
            }
            if event.type == .leftMouseDown, panOrigin != nil {
                finishPan()
            }
            guard let scrollView,
                  let window = scrollView.window else { return event }
            switch event.type {
            case .leftMouseDown:
                guard event.window === window,
                      ImageSurfaceInteraction(
                        modifierFlags: event.modifierFlags
                      ) == .navigate,
                      scrollView.contentView.convert(
                        scrollView.contentView.bounds,
                        to: nil
                      ).contains(event.locationInWindow) else {
                    return event
                }
                panOrigin = scrollView.contentView.bounds.origin
                panStart = event.locationInWindow
                NSCursor.closedHand.push()
                pushedCursor = true
                return nil
            case .leftMouseDragged:
                guard let panOrigin, let panStart else { return event }
                let translation = CGPoint(
                    x: event.locationInWindow.x - panStart.x,
                    y: event.locationInWindow.y - panStart.y
                )
                let proposed = CGRect(
                    origin: CGPoint(
                        x: panOrigin.x - translation.x,
                        y: panOrigin.y + translation.y
                    ),
                    size: scrollView.contentView.bounds.size
                )
                let constrained = scrollView.contentView.constrainBoundsRect(
                    proposed
                )
                scrollView.contentView.scroll(to: constrained.origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                return nil
            case .leftMouseUp:
                return event
            default:
                return event
            }
        }

        private func finishPan() {
            panOrigin = nil
            panStart = nil
            if pushedCursor { NSCursor.pop() }
            pushedCursor = false
        }
    }
}

private struct ZoomableImageView: View {
    let url: URL
    @State private var scale = 1.0
    @State private var lastScale = 1.0

    var body: some View {
        if let image = Self.thumbnail(at: url) {
            GeometryReader { geometry in
                let availableWidth = max(geometry.size.width - 80, 1)
                let availableHeight = max(geometry.size.height - 80, 1)
                let fitScale = min(
                    availableWidth / CGFloat(image.width),
                    availableHeight / CGFloat(image.height)
                )
                let width = CGFloat(image.width) * fitScale * scale
                let height = CGFloat(image.height) * fitScale * scale

                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height
                        )
                }
                .scrollIndicators(.hidden)
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value.magnification, 0.2), 8)
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
            .onChange(of: url) {
                scale = 1
                lastScale = 1
            }
        } else {
            ContentUnavailableView("Ingen förhandsvisning", systemImage: "photo")
        }
    }

    private static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8_192
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
