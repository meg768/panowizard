import Foundation
import MetalKit
import simd
import SwiftUI

struct SphericalPanoramaView: View {
    let url: URL
    let adjustments: PanoramaAdjustments
    let initialViewpoint: PanoramaViewpoint
    let onViewpointChange: (PanoramaViewpoint) -> Void
    let addsWorkspacePadding: Bool

    init(
        url: URL,
        adjustments: PanoramaAdjustments,
        initialViewpoint: PanoramaViewpoint,
        onViewpointChange: @escaping (PanoramaViewpoint) -> Void,
        addsWorkspacePadding: Bool = true
    ) {
        self.url = url
        self.adjustments = adjustments
        self.initialViewpoint = initialViewpoint
        self.onViewpointChange = onViewpointChange
        self.addsWorkspacePadding = addsWorkspacePadding
    }

    @ViewBuilder
    var body: some View {
        if addsWorkspacePadding {
            metalView
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .padding(.horizontal, 24)
                .padding(.top, 18)
        } else {
            metalView
        }
    }

    private var metalView: some View {
        SphericalMetalView(
            url: url,
            adjustments: adjustments,
            initialViewpoint: initialViewpoint,
            onViewpointChange: onViewpointChange
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SphericalMetalView: NSViewRepresentable {
    let url: URL
    let adjustments: PanoramaAdjustments
    let initialViewpoint: PanoramaViewpoint
    let onViewpointChange: (PanoramaViewpoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PanoramaMTKView {
        let view = PanoramaMTKView()
        context.coordinator.url = url
        context.coordinator.adjustments = adjustments
        context.coordinator.viewpoint = initialViewpoint
        context.coordinator.onViewpointChange = onViewpointChange
        context.coordinator.renderer = try? SphericalPanoramaRenderer(
            view: view,
            imageURL: url,
            adjustments: adjustments,
            initialViewpoint: initialViewpoint,
            onViewpointChange: { [weak coordinator = context.coordinator]
                viewpoint in
                coordinator?.viewpoint = viewpoint
                coordinator?.onViewpointChange?(viewpoint)
            }
        )
        view.panoramaRenderer = context.coordinator.renderer
        return view
    }

    func updateNSView(_ view: PanoramaMTKView, context: Context) {
        context.coordinator.onViewpointChange = onViewpointChange
        if context.coordinator.url != url {
            context.coordinator.url = url
            context.coordinator.renderer?.loadTexture(panoramaURL: url)
        }
        if context.coordinator.adjustments != adjustments {
            context.coordinator.adjustments = adjustments
            context.coordinator.renderer?.setAdjustments(adjustments)
        }
        if context.coordinator.viewpoint != initialViewpoint {
            context.coordinator.viewpoint = initialViewpoint
            context.coordinator.renderer?.setViewpoint(initialViewpoint)
        }
    }

    final class Coordinator {
        var renderer: SphericalPanoramaRenderer?
        var url: URL?
        var adjustments = PanoramaAdjustments.neutral
        var viewpoint = PanoramaViewpoint()
        var onViewpointChange: ((PanoramaViewpoint) -> Void)?
    }
}

private final class PanoramaMTKView: MTKView, ImageNavigationResponder {
    weak var panoramaRenderer: SphericalPanoramaRenderer?
    private var previousDragLocation: CGPoint?
    private var pushedDragCursor = false
    private var scrollZoomGesture = ImageSurfaceScrollGesture()

    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColorMake(0.025, 0.025, 0.03, 1)
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = true
        isPaused = true
        framebufferOnly = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        previousDragLocation = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.push()
        pushedDragCursor = true
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let previousDragLocation {
            let horizontal = location.x - previousDragLocation.x
            let vertical = location.y - previousDragLocation.y
            panoramaRenderer?.rotate(
                horizontal: Float(horizontal),
                vertical: Float(vertical)
            )
        }
        previousDragLocation = location
    }

    override func mouseUp(with event: NSEvent) {
        previousDragLocation = nil
        if pushedDragCursor { NSCursor.pop() }
        pushedDragCursor = false
    }

    override func scrollWheel(with event: NSEvent) {
        window?.makeFirstResponder(self)
        switch ImageSurfaceScroll.intent(for: event) {
        case .pan(let horizontal, let vertical):
            scrollZoomGesture.reset()
            panoramaRenderer?.endScrollZoom()
            panoramaRenderer?.rotate(
                horizontal: Float(horizontal),
                vertical: Float(vertical)
            )
        case .zoom(let delta):
            if scrollZoomGesture.beginsZoom(
                phase: event.phase,
                momentumPhase: event.momentumPhase
            ) {
                panoramaRenderer?.beginScrollZoom(
                    anchor: normalizedAnchor(for: event)
                )
            }
            panoramaRenderer?.zoom(by: Float(delta))
        case .ignore:
            if event.phase.contains(.began)
                || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
                scrollZoomGesture.reset()
                panoramaRenderer?.endScrollZoom()
            }
            break
        }
    }

    override func magnify(with event: NSEvent) {
        scrollZoomGesture.reset()
        panoramaRenderer?.endScrollZoom()
        window?.makeFirstResponder(self)
        panoramaRenderer?.magnify(
            by: Float(event.magnification),
            anchor: normalizedAnchor(for: event)
        )
    }

    func resetViewpoint() {
        scrollZoomGesture.reset()
        panoramaRenderer?.endScrollZoom()
        panoramaRenderer?.resetViewpoint()
    }

    @objc func zoomImageIn(_ sender: Any?) {
        scrollZoomGesture.reset()
        panoramaRenderer?.endScrollZoom()
        panoramaRenderer?.keyboardZoom(inward: true)
    }

    @objc func zoomImageOut(_ sender: Any?) {
        scrollZoomGesture.reset()
        panoramaRenderer?.endScrollZoom()
        panoramaRenderer?.keyboardZoom(inward: false)
    }

    @objc func resetImageView(_ sender: Any?) {
        resetViewpoint()
    }

    private func normalizedAnchor(for event: NSEvent) -> SIMD2<Float> {
        let location = convert(event.locationInWindow, from: nil)
        return SIMD2(
            Float(min(max(location.x / max(bounds.width, 1), 0), 1)),
            Float(min(max(location.y / max(bounds.height, 1), 0), 1))
        )
    }

}

@MainActor
private final class SphericalPanoramaRenderer: NSObject, MTKViewDelegate {
    private struct ScrollZoomAnchor {
        let viewportPosition: SIMD2<Float>
        let worldDirection: SIMD3<Float>
    }

    private struct Uniforms {
        var yaw: Float
        var pitch: Float
        var verticalFieldOfView: Float
        var aspectRatio: Float
        var lightAdjustments: SIMD4<Float>
        var toneAdjustments: SIMD4<Float>
        var colorAdjustments: SIMD4<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private weak var view: MTKView?
    private var texture: MTLTexture?
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var verticalFieldOfView: Float = 75 * .pi / 180
    private var scrollZoomAnchor: ScrollZoomAnchor?
    private var adjustments: PanoramaAdjustments
    private let initialViewpoint: PanoramaViewpoint
    private let onViewpointChange: (PanoramaViewpoint) -> Void

    init(
        view: MTKView,
        imageURL: URL,
        adjustments: PanoramaAdjustments,
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
        self.onViewpointChange = onViewpointChange
        self.adjustments = adjustments.sanitized
        self.initialViewpoint = initialViewpoint
        yaw = Float(initialViewpoint.yawRadians)
        pitch = Float(initialViewpoint.pitchRadians)
        verticalFieldOfView = Float(
            initialViewpoint.verticalFieldOfViewDegrees * .pi / 180
        )
        pipeline = try Self.makePipeline(device: device, pixelFormat: view.colorPixelFormat)
        super.init()
        view.delegate = self
        loadTexture(panoramaURL: imageURL)
    }

    func loadTexture(panoramaURL: URL) {
        let loader = MTKTextureLoader(device: device)
        texture = try? loader.newTexture(
            URL: panoramaURL,
            options: [
                .SRGB: false,
                .origin: MTKTextureLoader.Origin.topLeft,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue
            ]
        )
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func setAdjustments(_ adjustments: PanoramaAdjustments) {
        self.adjustments = adjustments.sanitized
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func setViewpoint(_ viewpoint: PanoramaViewpoint) {
        scrollZoomAnchor = nil
        yaw = Float(viewpoint.yawRadians)
        pitch = Float(viewpoint.pitchRadians)
        verticalFieldOfView = Float(
            viewpoint.verticalFieldOfViewDegrees * .pi / 180
        )
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func rotate(horizontal: Float, vertical: Float) {
        yaw -= horizontal * 0.005
        pitch = min(max(pitch + vertical * 0.005, -.pi / 2), .pi / 2)
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func beginScrollZoom(anchor: SIMD2<Float>) {
        let aspect = Float(view?.drawableSize.width ?? 1)
            / max(Float(view?.drawableSize.height ?? 1), 1)
        scrollZoomAnchor = ScrollZoomAnchor(
            viewportPosition: anchor,
            worldDirection: direction(
                at: anchor,
                fieldOfView: verticalFieldOfView,
                aspectRatio: aspect
            )
        )
    }

    func endScrollZoom() {
        scrollZoomAnchor = nil
    }

    func zoom(by delta: Float) {
        if scrollZoomAnchor == nil {
            beginScrollZoom(anchor: SIMD2(0.5, 0.5))
        }
        guard let scrollZoomAnchor else { return }
        setVerticalFieldOfView(
            verticalFieldOfView + delta * 0.006,
            anchoredAt: scrollZoomAnchor.viewportPosition,
            preserving: scrollZoomAnchor.worldDirection
        )
    }

    func magnify(by amount: Float, anchor: SIMD2<Float>) {
        setVerticalFieldOfView(
            verticalFieldOfView * (1 - amount),
            anchoredAt: anchor
        )
    }

    func keyboardZoom(inward: Bool) {
        let step = 10 * Float.pi / 180
        setVerticalFieldOfView(
            verticalFieldOfView + (inward ? -step : step),
            anchoredAt: SIMD2(0.5, 0.5)
        )
    }

    private func setVerticalFieldOfView(
        _ proposed: Float,
        anchoredAt anchor: SIMD2<Float>,
        preserving fixedDirection: SIMD3<Float>? = nil
    ) {
        let target = min(
            max(proposed, 30 * .pi / 180),
            150 * .pi / 180
        )
        guard abs(target - verticalFieldOfView) > 0.000_001 else { return }
        let aspect = Float(view?.drawableSize.width ?? 1)
            / max(Float(view?.drawableSize.height ?? 1), 1)
        let fixedDirection = fixedDirection ?? direction(
            at: anchor,
            fieldOfView: verticalFieldOfView,
            aspectRatio: aspect
        )
        verticalFieldOfView = target
        preserve(
            fixedDirection,
            at: anchor,
            fieldOfView: target,
            aspectRatio: aspect
        )
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func resetViewpoint() {
        scrollZoomAnchor = nil
        yaw = Float(initialViewpoint.yawRadians)
        pitch = Float(initialViewpoint.pitchRadians)
        verticalFieldOfView = Float(
            initialViewpoint.verticalFieldOfViewDegrees * .pi / 180
        )
        reportViewpoint()
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    private func direction(
        at anchor: SIMD2<Float>,
        fieldOfView: Float,
        aspectRatio: Float
    ) -> SIMD3<Float> {
        let tangent = tan(fieldOfView * 0.5)
        var direction = simd_normalize(SIMD3<Float>(
            (anchor.x * 2 - 1) * aspectRatio * tangent,
            (anchor.y * 2 - 1) * tangent,
            1
        ))
        let cosinePitch = cos(pitch)
        let sinePitch = sin(pitch)
        direction = SIMD3(
            direction.x,
            direction.y * cosinePitch - direction.z * sinePitch,
            direction.y * sinePitch + direction.z * cosinePitch
        )
        let cosineYaw = cos(yaw)
        let sineYaw = sin(yaw)
        return SIMD3(
            direction.x * cosineYaw + direction.z * sineYaw,
            direction.y,
            -direction.x * sineYaw + direction.z * cosineYaw
        )
    }

    private func preserve(
        _ fixedDirection: SIMD3<Float>,
        at anchor: SIMD2<Float>,
        fieldOfView: Float,
        aspectRatio: Float
    ) {
        let fixedLongitude = atan2(fixedDirection.x, fixedDirection.z)
        let fixedLatitude = asin(min(max(fixedDirection.y, -1), 1))
        for _ in 0..<4 {
            let current = direction(
                at: anchor,
                fieldOfView: fieldOfView,
                aspectRatio: aspectRatio
            )
            let currentLongitude = atan2(current.x, current.z)
            let currentLatitude = asin(min(max(current.y, -1), 1))
            yaw += wrappedAngle(fixedLongitude - currentLongitude)
            pitch = min(
                max(pitch + fixedLatitude - currentLatitude, -.pi / 2),
                .pi / 2
            )
        }
    }

    private func wrappedAngle(_ angle: Float) -> Float {
        atan2(sin(angle), cos(angle))
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
            lightAdjustments: SIMD4(
                Float(adjustments.exposure),
                Float(adjustments.brightness),
                Float(adjustments.contrast),
                Float(adjustments.highlights)
            ),
            toneAdjustments: SIMD4(
                Float(adjustments.shadows),
                Float(adjustments.whites),
                Float(adjustments.blacks),
                0
            ),
            colorAdjustments: SIMD4(
                Float(adjustments.temperature),
                Float(adjustments.tint),
                Float(adjustments.vibrance),
                Float(adjustments.saturation)
            )
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
        float4 lightAdjustments;
        float4 toneAdjustments;
        float4 colorAdjustments;
    };

    float3 srgbToLinear(float3 color) {
        float3 low = color / 12.92;
        float3 high = pow((color + 0.055) / 1.055, float3(2.4));
        return select(high, low, color <= 0.04045);
    }

    float3 applyAdjustments(
        float3 encodedColor,
        float2 coordinate,
        constant Uniforms &uniforms
    ) {
        float3 color = srgbToLinear(clamp(encodedColor, 0.0, 1.0));
        float exposure = uniforms.lightAdjustments.x;
        float brightness = uniforms.lightAdjustments.y / 100.0;
        float contrast = uniforms.lightAdjustments.z / 100.0;
        float highlights = uniforms.lightAdjustments.w / 100.0;
        float shadows = uniforms.toneAdjustments.x / 100.0;
        float whites = uniforms.toneAdjustments.y / 100.0;
        float blacks = uniforms.toneAdjustments.z / 100.0;
        float temperature = uniforms.colorAdjustments.x / 100.0;
        float tint = uniforms.colorAdjustments.y / 100.0;
        float vibrance = uniforms.colorAdjustments.z / 100.0;
        float saturation = uniforms.colorAdjustments.w / 100.0;

        color *= exp2(exposure);
        color += brightness * 0.25;
        float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        color += shadows * pow(clamp(1.0 - luminance, 0.0, 1.0), 2.0) * 0.35;
        color += highlights * pow(clamp(luminance, 0.0, 1.0), 2.0) * 0.35;
        float whiteMask = smoothstep(0.55, 1.0, luminance);
        float blackMask = 1.0 - smoothstep(0.0, 0.45, luminance);
        color *= 1.0 + whites * whiteMask * 0.35;
        color += blacks * blackMask * 0.20;
        color = (color - 0.18) * exp2(contrast) + 0.18;
        color = clamp(color, 0.0, 1.0);

        color.r += temperature * (1.0 - color.r) * 0.12;
        color.b -= temperature * (1.0 - color.b) * 0.12;
        color.r += tint * (1.0 - color.r) * 0.04;
        color.g -= tint * (1.0 - color.g) * 0.08;
        color.b += tint * (1.0 - color.b) * 0.04;

        luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        float maximum = max(color.r, max(color.g, color.b));
        float minimum = min(color.r, min(color.g, color.b));
        float chroma = maximum - minimum;
        float vibranceFactor = 1.0 + vibrance * (1.0 - clamp(chroma, 0.0, 1.0));
        color = mix(float3(luminance), color, vibranceFactor);
        color = mix(float3(luminance), color, 1.0 + saturation);

        return clamp(color, 0.0, 1.0);
    }

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
        constant Uniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler panoramaSampler(
            address::repeat,
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
        return float4(applyAdjustments(base.rgb, coordinate, uniforms), 1.0);
    }
    """

    private enum RendererError: Error {
        case metalUnavailable
    }
}
