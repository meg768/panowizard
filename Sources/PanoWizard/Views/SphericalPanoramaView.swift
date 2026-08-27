import Foundation
import MetalKit
import SwiftUI

struct SphericalPanoramaView: View {
    let url: URL
    let overlayURL: URL?
    let zenithOverlayURL: URL?
    let nadirRetouchURL: URL?
    let zenithRetouchURL: URL?
    let initialViewpoint: PanoramaViewpoint
    let onViewpointChange: (PanoramaViewpoint) -> Void

    var body: some View {
        SphericalMetalView(
            url: url,
            overlayURL: overlayURL,
            zenithOverlayURL: zenithOverlayURL,
            nadirRetouchURL: nadirRetouchURL,
            zenithRetouchURL: zenithRetouchURL,
            initialViewpoint: initialViewpoint,
            onViewpointChange: onViewpointChange
        )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .padding(.horizontal, 24)
            .padding(.top, 18)
    }
}

private struct SphericalMetalView: NSViewRepresentable {
    let url: URL
    let overlayURL: URL?
    let zenithOverlayURL: URL?
    let nadirRetouchURL: URL?
    let zenithRetouchURL: URL?
    let initialViewpoint: PanoramaViewpoint
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
            initialViewpoint: initialViewpoint,
            onViewpointChange: onViewpointChange
        )
        view.panoramaRenderer = context.coordinator.renderer
        return view
    }

    func updateNSView(_ view: PanoramaMTKView, context: Context) {
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
        fatalError("init(coder:) stöds inte")
    }

    override func mouseDown(with event: NSEvent) {
        previousDragLocation = convert(event.locationInWindow, from: nil)
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
    }

    override func scrollWheel(with event: NSEvent) {
        panoramaRenderer?.zoom(by: Float(event.scrollingDeltaY))
    }

    override func magnify(with event: NSEvent) {
        panoramaRenderer?.magnify(by: Float(event.magnification))
    }

    func resetViewpoint() {
        panoramaRenderer?.resetViewpoint()
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
    private let onViewpointChange: (PanoramaViewpoint) -> Void

    init(
        view: MTKView,
        imageURL: URL,
        overlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
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
        yaw = Float(initialViewpoint.yawRadians)
        pitch = Float(initialViewpoint.pitchRadians)
        verticalFieldOfView = Float(
            initialViewpoint.verticalFieldOfViewDegrees * .pi / 180
        )
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

    func resetViewpoint() {
        yaw = 0
        pitch = 0
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
            hasZenithRetouch: zenithRetouchTexture == nil ? 0 : 1
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
                float4 zenith = zenithOverlay.sample(
                    overlaySampler,
                    zenithCoordinate
                );
                base.rgb = mix(base.rgb, zenith.rgb, zenith.a);
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
            float4 repair = nadirOverlay.sample(
                overlaySampler,
                localCoordinate
            );
            base.rgb = mix(base.rgb, repair.rgb, repair.a);
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
