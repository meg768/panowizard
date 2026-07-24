import MetalKit
import SwiftUI

struct SphericalPanoramaView: View {
    let url: URL

    var body: some View {
        SphericalMetalView(url: url)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topLeading) {
                Label("Dra för att se dig omkring · rulla för att zooma", systemImage: "move.3d")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(14)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .padding(.horizontal, 24)
            .padding(.top, 18)
    }
}

private struct SphericalMetalView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PanoramaMTKView {
        let view = PanoramaMTKView()
        context.coordinator.renderer = try? SphericalPanoramaRenderer(view: view, imageURL: url)
        view.panoramaRenderer = context.coordinator.renderer
        return view
    }

    func updateNSView(_ view: PanoramaMTKView, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        context.coordinator.renderer?.loadTexture(from: url)
        view.resetViewpoint()
    }

    final class Coordinator {
        var renderer: SphericalPanoramaRenderer?
        var url: URL?
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
            panoramaRenderer?.rotate(
                horizontal: Float(location.x - previousDragLocation.x),
                vertical: Float(location.y - previousDragLocation.y)
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
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private weak var view: MTKView?
    private var texture: MTLTexture?
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var verticalFieldOfView: Float = 75 * .pi / 180

    init(view: MTKView, imageURL: URL) throws {
        guard
            let device = view.device,
            let commandQueue = device.makeCommandQueue()
        else {
            throw RendererError.metalUnavailable
        }

        self.device = device
        self.commandQueue = commandQueue
        self.view = view
        pipeline = try Self.makePipeline(device: device, pixelFormat: view.colorPixelFormat)
        super.init()
        view.delegate = self
        loadTexture(from: imageURL)
    }

    func loadTexture(from url: URL) {
        let loader = MTKTextureLoader(device: device)
        texture = try? loader.newTexture(
            URL: url,
            options: [
                .SRGB: true,
                .origin: MTKTextureLoader.Origin.topLeft,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue
            ]
        )
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func rotate(horizontal: Float, vertical: Float) {
        yaw -= horizontal * 0.005
        pitch = min(max(pitch + vertical * 0.005, -.pi / 2), .pi / 2)
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func zoom(by delta: Float) {
        verticalFieldOfView = min(max(verticalFieldOfView - delta * 0.006, 30 * .pi / 180), 105 * .pi / 180)
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func magnify(by amount: Float) {
        verticalFieldOfView = min(max(verticalFieldOfView * (1 - amount), 30 * .pi / 180), 105 * .pi / 180)
        view?.setNeedsDisplay(view?.bounds ?? .zero)
    }

    func resetViewpoint() {
        yaw = 0
        pitch = 0
        verticalFieldOfView = 75 * .pi / 180
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
            aspectRatio: Float(view.drawableSize.width / max(view.drawableSize.height, 1))
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
        return panorama.sample(panoramaSampler, coordinate);
    }
    """

    private enum RendererError: Error {
        case metalUnavailable
    }
}
