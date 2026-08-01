import AppKit
import ImageIO
import SwiftUI

struct PanoramaPreview: View {
    let panorama: PanoramaSet?
    let imageURL: URL?
    let isStitched: Bool
    let nadirOverlayURL: URL?
    let zenithOverlayURL: URL?
    let selectedSource: SourceImage?
    let maskData: Data?
    let brushDiameter: Double
    let zoom: Double
    let isErasing: Bool
    let isControlPointMask: Bool
    let isAdjustingNadir: Bool
    let adjustedPole: PanoramaPole
    let nadirAdjustment: NadirRepairAdjustment
    let nadirContentBounds: [Double]
    let initialViewpoint: PanoramaViewpoint
    let onNadirAdjustmentChange: (NadirRepairAdjustment) -> Void
    let onViewpointChange: (PanoramaViewpoint) -> Void
    let onMaskChange: (Data?) -> Void

    var body: some View {
        Group {
            if let panorama, let imageURL {
                if isStitched {
                    SphericalPanoramaView(
                        url: imageURL,
                        overlayURL: nadirOverlayURL,
                        zenithOverlayURL: zenithOverlayURL,
                        isAdjustingNadir: isAdjustingNadir,
                        adjustedPole: adjustedPole,
                        nadirAdjustment: nadirAdjustment,
                        nadirContentBounds: nadirContentBounds,
                        initialViewpoint: initialViewpoint,
                        onNadirAdjustmentChange: onNadirAdjustmentChange,
                        onViewpointChange: onViewpointChange
                    )
                } else if let selectedSource {
                    SourceMaskEditor(
                        image: selectedSource,
                        maskData: maskData,
                        brushDiameter: brushDiameter,
                        zoom: zoom,
                        isErasing: isErasing,
                        isControlPointMask: isControlPointMask,
                        onMaskChange: onMaskChange
                    )
                } else {
                    VStack(spacing: 12) {
                        ZoomableImageView(url: imageURL)
                        Text("\(panorama.images.count) källbilder väntar på sammanfogning")
                            .font(.callout)
                            .foregroundStyle(.secondary)
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
}

private struct SourceMaskEditor: View {
    let image: SourceImage
    let maskData: Data?
    let brushDiameter: Double
    let zoom: Double
    let isErasing: Bool
    let isControlPointMask: Bool
    let onMaskChange: (Data?) -> Void

    @State private var sourceImage: CGImage?
    @State private var maskImage: CGImage?
    @State private var activeStroke: [MaskPoint] = []
    @State private var visibleScrollRect = CGRect.zero
    @State private var zoomAnchor = UnitPoint.center
    @State private var hoverPoint: CGPoint?
    @State private var isSystemCursorHidden = false

    private let zoomAnchorID = "source-image-zoom-anchor"

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
                let displayedBrushRadius = CGFloat(brushDiameter) * displayScale / 2

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

                            Canvas { context, _ in
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
                                context.stroke(
                                    path,
                                    with: .color(
                                        isErasing
                                            ? .white.opacity(0.8)
                                            : (
                                                isControlPointMask
                                                    ? .orange.opacity(0.8)
                                                    : .red.opacity(0.75)
                                            )
                                    ),
                                    style: StrokeStyle(
                                        lineWidth: max(displayedBrushRadius * 2, 1),
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                            }
                            .allowsHitTesting(false)

                            Canvas { context, _ in
                                guard let hoverPoint else { return }
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
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    hoverPoint = value.location
                                    let point = MaskPoint(
                                        x: value.location.x / displaySize.width,
                                        y: value.location.y / displaySize.height
                                    )
                                    if activeStroke.last != point {
                                        activeStroke.append(point)
                                    }
                                }
                                .onEnded { _ in
                                    commitStroke(sourceImage: sourceImage)
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverPoint = location
                                hideSystemCursor()
                            case .ended:
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
                    .onScrollGeometryChange(for: CGRect.self) { scrollGeometry in
                        scrollGeometry.visibleRect
                    } action: { _, visibleRect in
                        visibleScrollRect = visibleRect
                    }
                    .onChange(of: zoom) { oldZoom, _ in
                        let oldSize = CGSize(
                            width: fitSize.width * oldZoom,
                            height: fitSize.height * oldZoom
                        )
                        let oldOrigin = CGPoint(
                            x: max((geometry.size.width - oldSize.width) / 2, 0),
                            y: max((geometry.size.height - oldSize.height) / 2, 0)
                        )
                        zoomAnchor = UnitPoint(
                            x: min(max(
                                (visibleScrollRect.midX - oldOrigin.x) / oldSize.width,
                                0
                            ), 1),
                            y: min(max(
                                (visibleScrollRect.midY - oldOrigin.y) / oldSize.height,
                                0
                            ), 1)
                        )
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo(zoomAnchorID, anchor: .center)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Bilden kunde inte läsas", systemImage: "photo")
            }
        }
        .background(.background)
        .overlay(alignment: .top) {
            Text(instruction)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 18)
                .allowsHitTesting(false)
        }
        .task(id: image.id) {
            sourceImage = Self.loadImage(at: image.url)
            maskImage = Self.loadImage(data: maskData)
            activeStroke = []
        }
        .onChange(of: maskData) {
            maskImage = Self.loadImage(data: maskData)
        }
        .onDisappear {
            showSystemCursor()
        }
    }

    private var instruction: String {
        if isErasing {
            return "Måla för att återställa bildens pixlar"
        }
        if isControlPointMask {
            return "Måla orange över rörliga objekt som ska ignoreras vid matchning"
        }
        return "Måla rött över sådant som inte ska användas"
    }

    private func commitStroke(sourceImage: CGImage) {
        guard !activeStroke.isEmpty else { return }
        let data = SourceMaskRasterizer.applying(
            stroke: activeStroke,
            radius: CGFloat(brushDiameter / 2),
            erasing: isErasing,
            controlPointExclusion: isControlPointMask,
            to: maskData,
            width: sourceImage.width,
            height: sourceImage.height
        )
        activeStroke = []
        onMaskChange(data)
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
