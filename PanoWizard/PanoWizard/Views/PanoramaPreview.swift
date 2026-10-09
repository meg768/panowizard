@preconcurrency import AppKit
import ImageIO
import SwiftUI

struct PanoramaPreview: View {
    let panorama: PanoramaSet?
    let imageURL: URL?
    let isStitched: Bool
    let adjustments: PanoramaAdjustments
    let selectedSource: SourceImage?
    let maskData: Data?
    let protectedMaskData: Data?
    let maskTool: SourceMaskTool
    let maskIntent: AppModel.SourceMaskIntent
    let initialViewpoint: PanoramaViewpoint
    let onViewpointChange: (PanoramaViewpoint) -> Void
    let addImages: () -> Void
    let canCreate: Bool
    let createPanorama: () -> Void
    let onMasksChange: (Data?, Data?) -> Void

    @State private var sourceViewports: [SourceImage.ID: SourceViewport] = [:]

    var body: some View {
        Group {
            if let panorama {
                if isStitched, let imageURL {
                    SphericalPanoramaView(
                        url: imageURL,
                        adjustments: adjustments,
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
                        Text("\(panorama.images.count) source images are waiting to be stitched")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Panorama to Preview", systemImage: "eye")
                    } description: {
                        Text(
                            "Create the panorama to preview it in 360°."
                        )
                    } actions: {
                        Button(action: createPanorama) { Label("Create", systemImage: "pano") }
                            .buttonStyle(WorkspaceToolbarPillStyle())
                            .disabled(!canCreate)
                    }
                    .opticalEmptyState()
                }
            } else {
                ContentUnavailableView {
                    Label("No Source Images", systemImage: "photo.badge.plus")
                } description: {
                    Text("To preview, first add source images and create a panorama.")
                } actions: {
                    VStack(spacing: 12) {
                        Button("Add", action: addImages)
                            .buttonStyle(WorkspaceToolbarPillStyle())
                        Text("PanoWizard reads metadata and arranges the images automatically.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .opticalEmptyState()
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
    @State private var scrollGeometry: ScrollGeometry?
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
                                    .opacity(MaskOverlayAppearance.committedOpacity)
                                    .allowsHitTesting(false)
                            }

                            if let protectedMaskImage {
                                Image(decorative: protectedMaskImage, scale: 1)
                                    .resizable()
                                    .frame(
                                        width: displaySize.width,
                                        height: displaySize.height
                                    )
                                    .opacity(MaskOverlayAppearance.committedOpacity)
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
                                        with: .color(strokeColor.opacity(
                                            MaskOverlayAppearance.activeStrokeOpacity
                                        )),
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
                                    drawMaskOperationIndicator(
                                        in: context,
                                        center: hoverPoint,
                                        radius: 6,
                                        isRemoving: previewIsErasing
                                    )
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
                                drawMaskOperationIndicator(
                                    in: context,
                                    center: hoverPoint,
                                    radius: displayedBrushRadius * 0.55,
                                    isRemoving: previewIsErasing
                                )
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
                            NativeImagePanMonitor(
                                onCommandAnchorChange: { anchor in
                                    if let anchor {
                                        prepareZoomAnchor(
                                            anchor,
                                            displaySize: displaySize
                                        )
                                    } else {
                                        pendingZoomAnchor = nil
                                    }
                                },
                                onCommandScroll: { delta, anchor in
                                    pendingZoomAnchor = anchor
                                    setZoom(zoom * exp(-delta * 0.006))
                                },
                                onZoomIn: {
                                    prepareZoomAnchor(
                                        .center,
                                        displaySize: displaySize
                                    )
                                    setZoom(zoom * 1.25)
                                },
                                onZoomOut: {
                                    prepareZoomAnchor(
                                        .center,
                                        displaySize: displaySize
                                    )
                                    setZoom(zoom / 1.25)
                                },
                                onReset: {
                                    zoomAnchor = .center
                                    pendingZoomAnchor = .center
                                    if zoom == 1 {
                                        proxy.scrollTo(
                                            zoomAnchorID,
                                            anchor: .center
                                        )
                                    } else {
                                        setZoom(1)
                                    }
                                }
                            )
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
                        modifierInteraction != .navigate || pointerGesture != nil
                    )
                    .scrollPosition($scrollPosition)
                    .onScrollGeometryChange(for: ScrollGeometry.self) { geometry in
                        geometry
                    } action: { _, geometry in
                        scrollGeometry = geometry
                        updateViewport(using: geometry)
                    }
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let start = magnificationStartZoom ?? zoom
                                if magnificationStartZoom == nil {
                                    magnificationStartZoom = zoom
                                    prepareZoomAnchor(
                                        value.startAnchor,
                                        displaySize: displaySize
                                    )
                                }
                                pendingZoomAnchor = value.startAnchor
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
                ContentUnavailableView("The Image Could Not Be Read", systemImage: "photo")
                .opticalEmptyState()
            }
        }
        .background(.background)
        .background {
            ImageSurfaceModifierMonitor { interaction in
                modifierInteraction = interaction
                updateCursorFeedback()
            }
        }
        .task(id: image) {
            pendingViewportCenter = viewport.center
            sourceImage = SourceImageRaster.load(
                image,
                maximumPixelSize: 12_000
            )
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
        viewport.zoom = min(max(zoom, 1), 16)
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
    }

    private var strokeColor: Color {
        if previewIsErasing { return .white }
        switch maskIntent {
        case .exclude: return .red
        case .protect: return .green
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
            erasing: activeGestureErases,
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
            erasing: activeGestureErases,
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

    private func drawMaskOperationIndicator(
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        isRemoving: Bool
    ) {
        var symbol = Path()
        symbol.move(to: CGPoint(x: center.x - radius, y: center.y))
        symbol.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        if !isRemoving {
            symbol.move(to: CGPoint(x: center.x, y: center.y - radius))
            symbol.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        }
        context.stroke(symbol, with: .color(.black.opacity(0.85)), lineWidth: 3)
        context.stroke(symbol, with: .color(.white), lineWidth: 1)
    }

    private func prepareZoomAnchor(
        _ viewportAnchor: UnitPoint,
        displaySize: CGSize
    ) {
        guard let geometry = scrollGeometry else {
            zoomAnchor = viewportAnchor
            pendingZoomAnchor = viewportAnchor
            return
        }
        let imageOrigin = CGPoint(
            x: max((geometry.contentSize.width - displaySize.width) / 2, 0),
            y: max((geometry.contentSize.height - displaySize.height) / 2, 0)
        )
        let contentPoint = CGPoint(
            x: geometry.visibleRect.minX
                + viewportAnchor.x * geometry.containerSize.width,
            y: geometry.visibleRect.minY
                + viewportAnchor.y * geometry.containerSize.height
        )
        zoomAnchor = UnitPoint(
            x: min(max(
                (contentPoint.x - imageOrigin.x) / max(displaySize.width, 1),
                0
            ), 1),
            y: min(max(
                (contentPoint.y - imageOrigin.y) / max(displaySize.height, 1),
                0
            ), 1)
        )
        pendingZoomAnchor = viewportAnchor
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

    private static func loadImage(data: Data?) -> CGImage? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
    let onCommandAnchorChange: (UnitPoint?) -> Void
    let onCommandScroll: (CGFloat, UnitPoint) -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onReset: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onReset = onReset
        view.onHierarchyChange = { [weak coordinator = context.coordinator,
                                    weak view] in
            guard let coordinator, let view else { return }
            coordinator.scrollView = view.enclosingScrollView
        }
        context.coordinator.commandView = view
        context.coordinator.onCommandAnchorChange = onCommandAnchorChange
        context.coordinator.onCommandScroll = onCommandScroll
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onReset = onReset
        context.coordinator.scrollView = view.enclosingScrollView
        context.coordinator.commandView = view
        context.coordinator.onCommandAnchorChange = onCommandAnchorChange
        context.coordinator.onCommandScroll = onCommandScroll
    }

    static func dismantleNSView(
        _ view: AttachmentView,
        coordinator: Coordinator
    ) {
        coordinator.uninstall()
    }

    final class AttachmentView: NSView, ImageNavigationResponder {
        var onHierarchyChange: (() -> Void)?
        var onZoomIn: () -> Void = {}
        var onZoomOut: () -> Void = {}
        var onReset: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        @objc func zoomImageIn(_ sender: Any?) { onZoomIn() }
        @objc func zoomImageOut(_ sender: Any?) { onZoomOut() }
        @objc func resetImageView(_ sender: Any?) { onReset() }

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
        weak var commandView: AttachmentView?
        var onCommandAnchorChange: (UnitPoint?) -> Void = { _ in }
        var onCommandScroll: (CGFloat, UnitPoint) -> Void = { _, _ in }
        private var monitor: Any?
        private var panOrigin: CGPoint?
        private var panStart: CGPoint?
        private var pushedCursor = false
        private var commandIsPressed = false
        private var scrollZoomAnchor: UnitPoint?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [
                    .leftMouseDown,
                    .leftMouseDragged,
                    .leftMouseUp,
                    .scrollWheel,
                    .magnify,
                    .flagsChanged
                ]
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
            if event.type == .flagsChanged {
                updateCommandAnchor(event: event)
                return event
            }
            if event.type == .leftMouseUp, panOrigin != nil {
                finishPan()
                return nil
            }
            if event.type == .leftMouseDown, panOrigin != nil {
                finishPan()
            }
            guard let scrollView,
                  let window = scrollView.window else { return event }
            let hitRect = scrollView.contentView.convert(
                scrollView.contentView.bounds,
                to: nil
            )
            if event.type == .scrollWheel || event.type == .magnify {
                guard event.window === window,
                      hitRect.contains(event.locationInWindow) else {
                    return event
                }
                window.makeFirstResponder(commandView)
                guard event.type == .scrollWheel else { return event }
                switch ImageSurfaceScroll.intent(for: event) {
                case .pan:
                    return event
                case .zoom(let delta):
                    guard commandIsPressed,
                          let scrollZoomAnchor else { return nil }
                    onCommandScroll(delta, scrollZoomAnchor)
                    return nil
                case .ignore:
                    return nil
                }
            }
            switch event.type {
            case .leftMouseDown:
                guard event.window === window,
                      hitRect.contains(event.locationInWindow) else {
                    return event
                }
                window.makeFirstResponder(commandView)
                guard ImageSurfaceInteraction(
                    modifierFlags: event.modifierFlags
                ) == .navigate else { return event }
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

        private func updateCommandAnchor(event: NSEvent) {
            let isPressed = event.modifierFlags.contains(.command)
            guard isPressed != commandIsPressed else { return }
            commandIsPressed = isPressed

            guard isPressed,
                  let scrollView,
                  let window = scrollView.window,
                  event.window == nil || event.window === window else {
                scrollZoomAnchor = nil
                onCommandAnchorChange(nil)
                return
            }
            let hitRect = scrollView.contentView.convert(
                scrollView.contentView.bounds,
                to: nil
            )
            let mouseInWindow = window.convertPoint(
                fromScreen: NSEvent.mouseLocation
            )
            guard hitRect.contains(mouseInWindow) else {
                scrollZoomAnchor = nil
                onCommandAnchorChange(nil)
                return
            }
            let anchor = UnitPoint(
                x: min(max(
                    (mouseInWindow.x - hitRect.minX) / max(hitRect.width, 1),
                    0
                ), 1),
                y: min(max(
                    1 - (mouseInWindow.y - hitRect.minY)
                        / max(hitRect.height, 1),
                    0
                ), 1)
            )
            scrollZoomAnchor = anchor
            onCommandAnchorChange(anchor)
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
            ContentUnavailableView("No Preview", systemImage: "photo")
            .opticalEmptyState()
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
