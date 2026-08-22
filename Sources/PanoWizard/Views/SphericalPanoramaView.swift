import Foundation
import MetalKit
import SwiftUI

struct SphericalPanoramaView: View {
    let url: URL
    let overlayURL: URL?
    let zenithOverlayURL: URL?
    let nadirRetouchURL: URL?
    let zenithRetouchURL: URL?
    let isAdjustingNadir: Bool
    let adjustedPole: PanoramaPole
    let nadirAdjustment: NadirRepairAdjustment
    let nadirContentBounds: [Double]
    let initialViewpoint: PanoramaViewpoint
    let onNadirAdjustmentChange: (NadirRepairAdjustment) -> Void
    let onViewpointChange: (PanoramaViewpoint) -> Void

    var body: some View {
        SphericalMetalView(
            url: url,
            overlayURL: overlayURL,
            zenithOverlayURL: zenithOverlayURL,
            nadirRetouchURL: nadirRetouchURL,
            zenithRetouchURL: zenithRetouchURL,
            isAdjustingNadir: isAdjustingNadir,
            adjustedPole: adjustedPole,
            nadirAdjustment: nadirAdjustment,
            nadirContentBounds: nadirContentBounds,
            initialViewpoint: initialViewpoint,
            onNadirAdjustmentChange: onNadirAdjustmentChange,
            onViewpointChange: onViewpointChange
        )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topLeading) {
                if isAdjustingNadir {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Justering · dra: flytta · hörn: perspektiv · ⌘-dra: rotera · ⌥-rulla: skala",
                            systemImage: "scope"
                        )
                        if overlayURL != nil || zenithOverlayURL != nil
                            || nadirRetouchURL != nil
                            || zenithRetouchURL != nil {
                            Label(
                                adjustmentDescription,
                                systemImage: "square.2.layers.3d.bottom.filled"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        .black.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .padding(14)
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .padding(.horizontal, 24)
            .padding(.top, 18)
    }

    private var adjustmentDescription: String {
        String(
            format: "%@ · %+.0f px · %+.0f px · %+.2f° · %.1f %%",
            adjustedPole.displayName,
            nadirAdjustment.translationX,
            nadirAdjustment.translationY,
            nadirAdjustment.rotationDegrees,
            nadirAdjustment.scale * 100
        )
    }
}

private struct SphericalMetalView: NSViewRepresentable {
    let url: URL
    let overlayURL: URL?
    let zenithOverlayURL: URL?
    let nadirRetouchURL: URL?
    let zenithRetouchURL: URL?
    let isAdjustingNadir: Bool
    let adjustedPole: PanoramaPole
    let nadirAdjustment: NadirRepairAdjustment
    let nadirContentBounds: [Double]
    let initialViewpoint: PanoramaViewpoint
    let onNadirAdjustmentChange: (NadirRepairAdjustment) -> Void
    let onViewpointChange: (PanoramaViewpoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PanoramaMTKView {
        let view = PanoramaMTKView()
        context.coordinator.url = url
        context.coordinator.overlayURL = overlayURL
        context.coordinator.zenithOverlayURL = zenithOverlayURL
        context.coordinator.nadirRetouchURL = nadirRetouchURL
        context.coordinator.zenithRetouchURL = zenithRetouchURL
        context.coordinator.renderer = try? SphericalPanoramaRenderer(
            view: view,
            imageURL: url,
            overlayURL: overlayURL,
            zenithOverlayURL: zenithOverlayURL,
            nadirRetouchURL: nadirRetouchURL,
            zenithRetouchURL: zenithRetouchURL,
            nadirAdjustment: nadirAdjustment,
            contentBounds: nadirContentBounds,
            isAdjustingNadir: isAdjustingNadir,
            adjustedPole: adjustedPole,
            initialViewpoint: initialViewpoint,
            onViewpointChange: onViewpointChange
        )
        view.panoramaRenderer = context.coordinator.renderer
        view.configureNadirAdjustment(
            nadirAdjustment,
            contentBounds: nadirContentBounds,
            isAdjusting: isAdjustingNadir,
            pole: adjustedPole,
            onChange: onNadirAdjustmentChange
        )
        return view
    }

    func updateNSView(_ view: PanoramaMTKView, context: Context) {
        view.configureNadirAdjustment(
            nadirAdjustment,
            contentBounds: nadirContentBounds,
            isAdjusting: isAdjustingNadir,
            pole: adjustedPole,
            onChange: onNadirAdjustmentChange
        )
        if context.coordinator.url != url
            || context.coordinator.overlayURL != overlayURL
            || context.coordinator.zenithOverlayURL != zenithOverlayURL
            || context.coordinator.nadirRetouchURL != nadirRetouchURL
            || context.coordinator.zenithRetouchURL != zenithRetouchURL {
            context.coordinator.url = url
            context.coordinator.overlayURL = overlayURL
            context.coordinator.zenithOverlayURL = zenithOverlayURL
            context.coordinator.nadirRetouchURL = nadirRetouchURL
            context.coordinator.zenithRetouchURL = zenithRetouchURL
            context.coordinator.renderer?.loadTextures(
                panoramaURL: url,
                overlayURL: overlayURL,
                zenithOverlayURL: zenithOverlayURL,
                nadirRetouchURL: nadirRetouchURL,
                zenithRetouchURL: zenithRetouchURL
            )
        }
    }

    final class Coordinator {
        var renderer: SphericalPanoramaRenderer?
        var url: URL?
        var overlayURL: URL?
        var zenithOverlayURL: URL?
        var nadirRetouchURL: URL?
        var zenithRetouchURL: URL?
    }
}

private final class PanoramaMTKView: MTKView {
    weak var panoramaRenderer: SphericalPanoramaRenderer?
    private var previousDragLocation: CGPoint?
    private var isAdjustingNadir = false
    private var adjustedPole = PanoramaPole.nadir
    private var nadirAdjustment = NadirRepairAdjustment.identity
    private var contentBounds = [0.0, 0.0, 1.0, 1.0]
    private var onNadirAdjustmentChange: ((NadirRepairAdjustment) -> Void)?
    private var activeCorner: Int?
    private let cornerLayers = (0..<4).map { _ in CAShapeLayer() }
    private let outlineLayer = CAShapeLayer()

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColorMake(0.025, 0.025, 0.03, 1)
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = true
        isPaused = true
        framebufferOnly = true
        wantsLayer = true
        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = NSColor.systemYellow.cgColor
        outlineLayer.lineWidth = 1.5
        outlineLayer.lineDashPattern = [5, 4]
        layer?.addSublayer(outlineLayer)
        for handle in cornerLayers {
            handle.fillColor = NSColor.systemYellow.cgColor
            handle.strokeColor = NSColor.black.withAlphaComponent(0.75).cgColor
            handle.lineWidth = 2
            layer?.addSublayer(handle)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) stöds inte")
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        activeCorner = isAdjustingNadir
            ? handlePoints.firstIndex { hypot($0.x - location.x, $0.y - location.y) < 18 }
            : nil
        previousDragLocation = location
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let previousDragLocation {
            let horizontal = location.x - previousDragLocation.x
            let vertical = location.y - previousDragLocation.y
            if isAdjustingNadir {
                var adjustment = nadirAdjustment
                if let activeCorner {
                    var offsets = adjustment.resolvedCornerOffsets
                    let localScale = 1_600 / max(min(bounds.width, bounds.height) - 120, 200)
                    offsets[activeCorner * 2] += horizontal * localScale
                    offsets[activeCorner * 2 + 1] -= vertical * localScale
                    adjustment.cornerOffsets = offsets
                } else if event.modifierFlags.contains(.command) {
                    adjustment.rotationDegrees = min(max(
                        adjustment.rotationDegrees + horizontal * 0.12,
                        -45
                    ), 45)
                } else {
                    adjustment.translationX = min(max(
                        adjustment.translationX + horizontal,
                        -500
                    ), 500)
                    adjustment.translationY = min(max(
                        adjustment.translationY - vertical,
                        -500
                    ), 500)
                }
                applyNadirAdjustment(adjustment)
            } else {
                panoramaRenderer?.rotate(
                    horizontal: Float(horizontal),
                    vertical: Float(vertical)
                )
            }
        }
        previousDragLocation = location
    }

    override func mouseUp(with event: NSEvent) {
        previousDragLocation = nil
        activeCorner = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if isAdjustingNadir && event.modifierFlags.contains(.option) {
            var adjustment = nadirAdjustment
            adjustment.scale = min(max(
                adjustment.scale * exp(event.scrollingDeltaY * 0.008),
                0.2
            ), 8)
            applyNadirAdjustment(adjustment)
        } else {
            panoramaRenderer?.zoom(by: Float(event.scrollingDeltaY))
            updateHandles()
        }
    }

    override func magnify(with event: NSEvent) {
        if isAdjustingNadir && event.modifierFlags.contains(.option) {
            var adjustment = nadirAdjustment
            adjustment.scale = min(max(
                adjustment.scale * (1 + event.magnification),
                0.2
            ), 8)
            applyNadirAdjustment(adjustment)
        } else {
            panoramaRenderer?.magnify(by: Float(event.magnification))
            updateHandles()
        }
    }

    func resetViewpoint() {
        panoramaRenderer?.resetViewpoint()
    }

    func configureNadirAdjustment(
        _ adjustment: NadirRepairAdjustment,
        contentBounds: [Double],
        isAdjusting: Bool,
        pole: PanoramaPole,
        onChange: @escaping (NadirRepairAdjustment) -> Void
    ) {
        let startedAdjusting = isAdjusting && !isAdjustingNadir
        nadirAdjustment = adjustment
        self.contentBounds = contentBounds.count == 4
            ? contentBounds
            : [0, 0, 1, 1]
        isAdjustingNadir = isAdjusting
        adjustedPole = pole
        onNadirAdjustmentChange = onChange
        panoramaRenderer?.setNadirAdjustment(
            adjustment,
            contentBounds: self.contentBounds,
            isAdjusting: isAdjusting,
            pole: pole
        )
        if startedAdjusting {
            panoramaRenderer?.focus(pole)
        }
        updateHandles()
    }

    private func applyNadirAdjustment(
        _ adjustment: NadirRepairAdjustment
    ) {
        nadirAdjustment = adjustment
        panoramaRenderer?.setNadirAdjustment(
            adjustment,
            contentBounds: contentBounds,
            isAdjusting: isAdjustingNadir,
            pole: adjustedPole
        )
        onNadirAdjustmentChange?(adjustment)
        updateHandles()
    }

    override func layout() {
        super.layout()
        updateHandles()
    }

    private var handlePoints: [CGPoint] {
        let projectionScale = 0.2886751346
        let fieldOfView = panoramaRenderer?.verticalFieldOfViewRadians
            ?? 75.0 * .pi / 180.0
        let tangent = tan(fieldOfView / 2)
        let localToScreen = bounds.height / (2 * projectionScale * tangent)
        let x = contentBounds[0]
        let y = contentBounds[1]
        let width = contentBounds[2]
        let height = contentBounds[3]
        let base = [
            CGPoint(x: x, y: y),
            CGPoint(x: x + width, y: y),
            CGPoint(x: x + width, y: y + height),
            CGPoint(x: x, y: y + height)
        ]
        let center = CGPoint(x: 0.5, y: 0.5)
        let pixelScale = localToScreen / 1_600
        let offsets = nadirAdjustment.resolvedCornerOffsets
        let angle = -nadirAdjustment.rotationDegrees * .pi / 180
        let cosine = cos(angle) * nadirAdjustment.scale
        let sine = sin(angle) * nadirAdjustment.scale
        return base.enumerated().map { index, point in
            let localX = (point.x - center.x) * localToScreen
            let localY = -(point.y - center.y) * localToScreen
            let transformedX = localX * cosine - localY * sine
            let transformedY = localX * sine + localY * cosine
            return CGPoint(
                x: bounds.midX
                    + transformedX
                    + (nadirAdjustment.translationX + offsets[index * 2])
                        * pixelScale,
                y: bounds.midY
                    + transformedY
                    - (nadirAdjustment.translationY + offsets[index * 2 + 1])
                        * pixelScale
            )
        }
    }

    private func updateHandles() {
        let visible = isAdjustingNadir
        outlineLayer.isHidden = !visible
        cornerLayers.forEach { $0.isHidden = !visible }
        guard visible else { return }
        let points = handlePoints
        let path = CGMutablePath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        outlineLayer.path = path
        for (layer, point) in zip(cornerLayers, points) {
            layer.path = CGPath(
                ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14),
                transform: nil
            )
        }
    }
}

@MainActor
private final class SphericalPanoramaRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var yaw: Float
        var pitch: Float
        var verticalFieldOfView: Float
        var aspectRatio: Float
        var hasOverlay: UInt32
        var hasZenithOverlay: UInt32
        var hasNadirRetouch: UInt32
        var hasZenithRetouch: UInt32
        var adjustedPole: UInt32
        var overlayTranslationX: Float
        var overlayTranslationY: Float
        var overlayRotation: Float
        var overlayScale: Float
        var overlayOpacity: Float
        var perspective0: SIMD3<Float>
        var perspective1: SIMD3<Float>
        var perspective2: SIMD3<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private weak var view: MTKView?
    private var texture: MTLTexture?
    private var overlayTexture: MTLTexture?
    private var zenithOverlayTexture: MTLTexture?
    private var nadirRetouchTexture: MTLTexture?
    private var zenithRetouchTexture: MTLTexture?
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var verticalFieldOfView: Float = 75 * .pi / 180
    private var nadirAdjustment: NadirRepairAdjustment
    private var contentBounds: [Double]
    private var overlayOpacity: Float
    private var adjustedPole: PanoramaPole
    private let onViewpointChange: (PanoramaViewpoint) -> Void

    init(
        view: MTKView,
        imageURL: URL,
        overlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        nadirAdjustment: NadirRepairAdjustment,
        contentBounds: [Double],
        isAdjustingNadir: Bool,
        adjustedPole: PanoramaPole,
        initialViewpoint: PanoramaViewpoint,
        onViewpointChange: @escaping (PanoramaViewpoint) -> Void
    ) throws {
        guard
            let device = view.device,
            let commandQueue = device.makeCommandQueue()
        else {
            throw RendererError.metalUnavailable
        }

        self.device = device
        self.commandQueue = commandQueue
        self.view = view
        self.nadirAdjustment = nadirAdjustment
        self.contentBounds = contentBounds
        self.adjustedPole = adjustedPole
        self.onViewpointChange = onViewpointChange
        yaw = Float(initialViewpoint.yawRadians)
        pitch = Float(initialViewpoint.pitchRadians)
        verticalFieldOfView = Float(
            initialViewpoint.verticalFieldOfViewDegrees * .pi / 180
        )
        overlayOpacity = isAdjustingNadir ? 0.68 : 1
        pipeline = try Self.makePipeline(device: device, pixelFormat: view.colorPixelFormat)
        super.init()
        view.delegate = self
        loadTextures(
            panoramaURL: imageURL,
            overlayURL: overlayURL,
            zenithOverlayURL: zenithOverlayURL,
            nadirRetouchURL: nadirRetouchURL,
            zenithRetouchURL: zenithRetouchURL
        )
    }

    func loadTextures(
        panoramaURL: URL,
        overlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?
    ) {
        let loader = MTKTextureLoader(device: device)
        texture = try? loader.newTexture(
            URL: panoramaURL,
            options: [
                .SRGB: true,
                .origin: MTKTextureLoader.Origin.topLeft,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue
            ]
        )
        if let overlayURL {
            overlayTexture = try? loader.newTexture(
                URL: overlayURL,
                options: [
                    .SRGB: true,
                    .origin: MTKTextureLoader.Origin.topLeft,
                    .textureUsage: MTLTextureUsage.shaderRead.rawValue
                ]
            )
            reportViewpoint()
        } else {
            overlayTexture = nil
            reportViewpoint()
        }
        if let zenithOverlayURL {
            zenithOverlayTexture = try? loader.newTexture(
                URL: zenithOverlayURL,
                options: [
                    .SRGB: true,
                    .origin: MTKTextureLoader.Origin.topLeft,
                    .textureUsage: MTLTextureUsage.shaderRead.rawValue
                ]
            )
        } else {
            zenithOverlayTexture = nil
        }
        if let nadirRetouchURL {
            nadirRetouchTexture = try? loader.newTexture(
                URL: nadirRetouchURL,
                options: [
                    .SRGB: true,
                    .origin: MTKTextureLoader.Origin.topLeft,
                    .textureUsage: MTLTextureUsage.shaderRead.rawValue
                ]
            )
        } else {
            nadirRetouchTexture = nil
        }
        if let zenithRetouchURL {
            zenithRetouchTexture = try? loader.newTexture(
                URL: zenithRetouchURL,
                options: [
                    .SRGB: true,
                    .origin: MTKTextureLoader.Origin.topLeft,
                    .textureUsage: MTLTextureUsage.shaderRead.rawValue
                ]
            )
        } else {
            zenithRetouchTexture = nil
        }
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func rotate(horizontal: Float, vertical: Float) {
        yaw -= horizontal * 0.005
        pitch = min(max(pitch + vertical * 0.005, -.pi / 2), .pi / 2)
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func zoom(by delta: Float) {
        verticalFieldOfView = min(
            max(verticalFieldOfView - delta * 0.006, 30 * .pi / 180),
            150 * .pi / 180
        )
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func magnify(by amount: Float) {
        verticalFieldOfView = min(
            max(verticalFieldOfView * (1 - amount), 30 * .pi / 180),
            150 * .pi / 180
        )
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    var verticalFieldOfViewRadians: CGFloat {
        CGFloat(verticalFieldOfView)
    }

    func resetViewpoint() {
        yaw = 0
        pitch = 0
        verticalFieldOfView = 75 * .pi / 180
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func focus(_ pole: PanoramaPole) {
        yaw = 0
        pitch = pole == .zenith ? -.pi / 2 : .pi / 2
        verticalFieldOfView = 75 * .pi / 180
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    private func reportViewpoint() {
        let viewpoint = PanoramaViewpoint(
            yawRadians: Double(yaw),
            pitchRadians: Double(pitch),
            verticalFieldOfViewDegrees: Double(
                verticalFieldOfView * 180 / .pi
            )
        )
        let callback = onViewpointChange
        DispatchQueue.main.async {
            callback(viewpoint)
        }
    }

    func setNadirAdjustment(
        _ adjustment: NadirRepairAdjustment,
        contentBounds: [Double],
        isAdjusting: Bool,
        pole: PanoramaPole
    ) {
        nadirAdjustment = adjustment
        self.contentBounds = contentBounds
        adjustedPole = pole
        overlayOpacity = isAdjusting ? 0.68 : 1
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
        guard
            let texture,
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        var uniforms = Uniforms(
            yaw: yaw,
            pitch: pitch,
            verticalFieldOfView: verticalFieldOfView,
            aspectRatio: Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
            hasOverlay: overlayTexture == nil ? 0 : 1,
            hasZenithOverlay: zenithOverlayTexture == nil ? 0 : 1,
            hasNadirRetouch: nadirRetouchTexture == nil ? 0 : 1,
            hasZenithRetouch: zenithRetouchTexture == nil ? 0 : 1,
            adjustedPole: adjustedPole == .zenith ? 1 : 2,
            overlayTranslationX: Float(nadirAdjustment.translationX / 1_600),
            overlayTranslationY: Float(nadirAdjustment.translationY / 1_600),
            overlayRotation: Float(
                nadirAdjustment.rotationDegrees * .pi / 180
            ),
            overlayScale: Float(nadirAdjustment.scale),
            overlayOpacity: overlayOpacity,
            perspective0: perspectiveInverseRows[0],
            perspective1: perspectiveInverseRows[1],
            perspective2: perspectiveInverseRows[2]
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(overlayTexture, index: 1)
        encoder.setFragmentTexture(zenithOverlayTexture, index: 2)
        encoder.setFragmentTexture(nadirRetouchTexture, index: 3)
        encoder.setFragmentTexture(zenithRetouchTexture, index: 4)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private var perspectiveInverseRows: [SIMD3<Float>] {
        let o = nadirAdjustment.resolvedCornerOffsets.map { Float($0 / 1_600) }
        let bounds = contentBounds.count == 4
            ? contentBounds.map(Float.init)
            : [0, 0, 1, 1]
        let left = bounds[0]
        let top = bounds[1]
        let right = left + bounds[2]
        let bottom = top + bounds[3]
        let p = [
            SIMD2<Float>(left + o[0], top + o[1]),
            SIMD2<Float>(right + o[2], top + o[3]),
            SIMD2<Float>(right + o[4], bottom + o[5]),
            SIMD2<Float>(left + o[6], bottom + o[7])
        ]
        let source = [
            SIMD2<Float>(left, top),
            SIMD2<Float>(right, top),
            SIMD2<Float>(right, bottom),
            SIMD2<Float>(left, bottom)
        ]
        return Self.inverseHomography(from: source, to: p)
    }

    private static func inverseHomography(
        from source: [SIMD2<Float>],
        to p: [SIMD2<Float>]
    ) -> [SIMD3<Float>] {
        let sourceWidth = max(source[1].x - source[0].x, 0.0001)
        let sourceHeight = max(source[3].y - source[0].y, 0.0001)
        let normalized = p.map {
            SIMD2<Float>(
                ($0.x - source[0].x) / sourceWidth,
                ($0.y - source[0].y) / sourceHeight
            )
        }
        let dx1 = normalized[1].x - normalized[2].x
        let dx2 = normalized[3].x - normalized[2].x
        let dx3 = normalized[0].x - normalized[1].x
            + normalized[2].x - normalized[3].x
        let dy1 = normalized[1].y - normalized[2].y
        let dy2 = normalized[3].y - normalized[2].y
        let dy3 = normalized[0].y - normalized[1].y
            + normalized[2].y - normalized[3].y
        let denominator = dx1 * dy2 - dx2 * dy1
        let g = abs(denominator) < 0.000_001 ? 0 : (dx3 * dy2 - dx2 * dy3) / denominator
        let h = abs(denominator) < 0.000_001 ? 0 : (dx1 * dy3 - dx3 * dy1) / denominator
        let forward = [
            normalized[1].x - normalized[0].x + g * normalized[1].x,
            normalized[3].x - normalized[0].x + h * normalized[3].x,
            normalized[0].x,
            normalized[1].y - normalized[0].y + g * normalized[1].y,
            normalized[3].y - normalized[0].y + h * normalized[3].y,
            normalized[0].y,
            g, h, 1
        ]
        let unitToSource: [Float] = [
            sourceWidth, 0, source[0].x,
            0, sourceHeight, source[0].y,
            0, 0, 1
        ]
        let sourceToUnit: [Float] = [
            1 / sourceWidth, 0, -source[0].x / sourceWidth,
            0, 1 / sourceHeight, -source[0].y / sourceHeight,
            0, 0, 1
        ]
        let f = multiply3x3(
            multiply3x3(unitToSource, forward),
            sourceToUnit
        )
        let a = f
        let determinant = a[0] * (a[4] * a[8] - a[5] * a[7])
            - a[1] * (a[3] * a[8] - a[5] * a[6])
            + a[2] * (a[3] * a[7] - a[4] * a[6])
        guard abs(determinant) > 0.000_001 else {
            return [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        }
        return [
            SIMD3(a[4] * a[8] - a[5] * a[7], a[2] * a[7] - a[1] * a[8], a[1] * a[5] - a[2] * a[4]) / determinant,
            SIMD3(a[5] * a[6] - a[3] * a[8], a[0] * a[8] - a[2] * a[6], a[2] * a[3] - a[0] * a[5]) / determinant,
            SIMD3(a[3] * a[7] - a[4] * a[6], a[1] * a[6] - a[0] * a[7], a[0] * a[4] - a[1] * a[3]) / determinant
        ]
    }

    private static func multiply3x3(
        _ left: [Float],
        _ right: [Float]
    ) -> [Float] {
        (0..<9).map { index in
            let row = index / 3
            let column = index % 3
            return (0..<3).reduce(0) {
                $0 + left[row * 3 + $1] * right[$1 * 3 + column]
            }
        }
    }

    private static func makePipeline(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "panoramaVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "panoramaFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 ndc;
    };

    struct Uniforms {
        float yaw;
        float pitch;
        float verticalFieldOfView;
        float aspectRatio;
        uint hasOverlay;
        uint hasZenithOverlay;
        uint hasNadirRetouch;
        uint hasZenithRetouch;
        uint adjustedPole;
        float overlayTranslationX;
        float overlayTranslationY;
        float overlayRotation;
        float overlayScale;
        float overlayOpacity;
        float3 perspective0;
        float3 perspective1;
        float3 perspective2;
    };

    vertex VertexOut panoramaVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.ndc = positions[vertexID];
        return out;
    }

    fragment float4 panoramaFragment(
        VertexOut in [[stage_in]],
        texture2d<float> panorama [[texture(0)]],
        texture2d<float> nadirOverlay [[texture(1)]],
        texture2d<float> zenithOverlay [[texture(2)]],
        texture2d<float> nadirRetouch [[texture(3)]],
        texture2d<float> zenithRetouch [[texture(4)]],
        constant Uniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler panoramaSampler(
            address::repeat,
            filter::linear,
            mip_filter::linear
        );
        constexpr sampler overlaySampler(
            address::clamp_to_zero,
            filter::linear,
            mip_filter::linear
        );

        float tangent = tan(uniforms.verticalFieldOfView * 0.5);
        float3 direction = normalize(float3(
            in.ndc.x * uniforms.aspectRatio * tangent,
            in.ndc.y * tangent,
            1.0
        ));

        float cosPitch = cos(uniforms.pitch);
        float sinPitch = sin(uniforms.pitch);
        direction = float3(
            direction.x,
            direction.y * cosPitch - direction.z * sinPitch,
            direction.y * sinPitch + direction.z * cosPitch
        );

        float cosYaw = cos(uniforms.yaw);
        float sinYaw = sin(uniforms.yaw);
        direction = float3(
            direction.x * cosYaw + direction.z * sinYaw,
            direction.y,
            -direction.x * sinYaw + direction.z * cosYaw
        );

        float longitude = atan2(direction.x, direction.z);
        float latitude = asin(clamp(direction.y, -1.0, 1.0));
        float2 coordinate = float2(
            0.5 + longitude / (2.0 * M_PI_F),
            0.5 - latitude / M_PI_F
        );
        float4 base = panorama.sample(panoramaSampler, coordinate);
        if (uniforms.hasZenithOverlay != 0) {
            float3 zenithRay = float3(
                direction.x,
                direction.z,
                direction.y
            );
            if (zenithRay.z > 0.0001) {
                constexpr float zenithProjectionScale = 0.2886751346;
                float2 zenithCoordinate = float2(0.5)
                    + zenithProjectionScale * zenithRay.xy / zenithRay.z;
                if (uniforms.adjustedPole == 1) {
                    float3 pc = float3(zenithCoordinate, 1.0);
                    pc = float3(
                        dot(uniforms.perspective0, pc),
                        dot(uniforms.perspective1, pc),
                        dot(uniforms.perspective2, pc)
                    );
                    zenithCoordinate = pc.xy / max(pc.z, 0.0001);
                    float2 zc = zenithCoordinate - float2(0.5)
                        - float2(uniforms.overlayTranslationX,
                                 uniforms.overlayTranslationY);
                    float zcos = cos(-uniforms.overlayRotation);
                    float zsin = sin(-uniforms.overlayRotation);
                    zc = float2(zc.x * zcos - zc.y * zsin,
                                zc.x * zsin + zc.y * zcos)
                        / max(uniforms.overlayScale, 0.01);
                    zenithCoordinate = zc + float2(0.5);
                }
                float4 zenith = zenithOverlay.sample(
                    overlaySampler,
                    zenithCoordinate
                );
                float zenithOpacity = zenith.a
                    * (uniforms.adjustedPole == 1
                        ? uniforms.overlayOpacity : 1.0);
                base.rgb = mix(base.rgb, zenith.rgb, zenithOpacity);
            }
        }
        if (uniforms.hasZenithRetouch != 0) {
            float3 zenithRay = float3(
                direction.x,
                direction.z,
                direction.y
            );
            if (zenithRay.z > 0.0001) {
                float2 retouchCoordinate = float2(0.5)
                    + 0.5 * zenithRay.xy / zenithRay.z;
                float4 retouch = zenithRetouch.sample(
                    overlaySampler,
                    retouchCoordinate
                );
                base.rgb = mix(base.rgb, retouch.rgb, retouch.a);
            }
        }
        if (uniforms.hasOverlay == 0 && uniforms.hasNadirRetouch == 0) {
            return float4(base.rgb, 1.0);
        }
        float3 localRay = float3(
            direction.x,
            -direction.z,
            -direction.y
        );
        if (localRay.z <= 0.0001) {
            return base;
        }
        if (uniforms.hasOverlay != 0) {
            constexpr float localProjectionScale = 0.2886751346;
            float2 localCoordinate = float2(0.5)
                + localProjectionScale * localRay.xy / localRay.z;
            float3 perspectiveCoordinate = float3(localCoordinate, 1.0);
            float2 repairCoordinate = localCoordinate;
            if (uniforms.adjustedPole == 2) {
                perspectiveCoordinate = float3(
                    dot(uniforms.perspective0, perspectiveCoordinate),
                    dot(uniforms.perspective1, perspectiveCoordinate),
                    dot(uniforms.perspective2, perspectiveCoordinate)
                );
                localCoordinate = perspectiveCoordinate.xy
                    / max(perspectiveCoordinate.z, 0.0001);
                float2 centered = localCoordinate
                    - float2(0.5)
                    - float2(
                        uniforms.overlayTranslationX,
                        uniforms.overlayTranslationY
                    );
                float cosine = cos(-uniforms.overlayRotation);
                float sine = sin(-uniforms.overlayRotation);
                centered = float2(
                    centered.x * cosine - centered.y * sine,
                    centered.x * sine + centered.y * cosine
                ) / max(uniforms.overlayScale, 0.01);
                repairCoordinate = centered + float2(0.5);
            }
            float4 repair = nadirOverlay.sample(
                overlaySampler,
                repairCoordinate
            );
            float repairOpacity = repair.a * uniforms.overlayOpacity;
            base.rgb = mix(base.rgb, repair.rgb, repairOpacity);
        }
        if (uniforms.hasNadirRetouch != 0) {
            float2 retouchCoordinate = float2(0.5)
                + 0.5 * localRay.xy / localRay.z;
            float4 retouch = nadirRetouch.sample(
                overlaySampler,
                retouchCoordinate
            );
            base.rgb = mix(base.rgb, retouch.rgb, retouch.a);
        }
        return float4(base.rgb, 1.0);
    }
    """

    private enum RendererError: Error {
        case metalUnavailable
    }
}
