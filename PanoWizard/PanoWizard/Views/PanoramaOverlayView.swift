import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct PanoramaOverlayView: View {
    @Bindable var model: AppModel
    @State private var showsDialog = false
    @State private var panoramaImage: CGImage?

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, min(geometry.size.width - 48, (geometry.size.height - 200) * 2))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overlay").font(.title2.bold())
                        Text("Use AI to adjust the whole panorama.").foregroundStyle(.secondary)
                    }
                    VStack(spacing: 16) {
                        ZStack {
                            Color.black.opacity(0.2)
                            if let panoramaImage {
                                Image(decorative: panoramaImage, scale: 1).resizable().scaledToFit()
                            } else {
                                Text("Create a panorama to get started.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: width, height: width / 2)
                        .clipped()
                        .accessibilityIdentifier("overlay-panorama-2to1")
                        if model.overlayURL != nil {
                            overlayToolbar.frame(width: width)
                        } else {
                            Button("Create AI overlay…") { showsDialog = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.basePanoramaURL == nil || model.phase != .ready)
                                .frame(width: width, alignment: .trailing)
                        }
                    }.frame(maxWidth: .infinity)
                    Text("The original panorama is preserved. Save the project to keep the overlay.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
        }
        .task(id: model.currentPanoramaURL) {
            let url = model.currentPanoramaURL
            let image = await Task.detached(priority: .userInitiated) {
                url.flatMap { OverlayImageIO.read(url: $0) }
            }.value
            guard !Task.isCancelled else { return }
            panoramaImage = image
        }
        .sheet(isPresented: $showsDialog) {
            PanoramaOverlayDialog(model: model) { showsDialog = false }
        }
    }

    private var overlayToolbar: some View {
        HStack(spacing: 12) {
            Toggle("Use overlay", isOn: Binding(
                get: { model.project.overlayEnabled != false },
                set: { model.setOverlayEnabled($0) }
            ))
            .toggleStyle(.switch)
            .focusable(false)
            Spacer()
            Button("Edit…") { showsDialog = true }
                .buttonStyle(.borderedProminent)
            Button("Delete Overlay", systemImage: "trash", role: .destructive) {
                model.removeOverlay()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .disabled(model.phase != .ready)
    }
}

private struct PanoramaOverlayDialog: View {
    @Bindable var model: AppModel
    let onDismiss: () -> Void
    @State private var instruction: String
    @State private var before: CGImage?
    @State private var after: CGImage?
    @State private var showsAfter: Bool
    @State private var generatedData: Data?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var generation: Task<Void, Never>?
    @State private var showsKey = false
    @State private var generatedSize: CGSize?
    private let keyStore = OpenAIAPIKeyStore()
    private static let defaultInstruction = "Adjust the panorama while preserving its geometry, people and existing scene. Match exposure and color naturally."

    init(model: AppModel, onDismiss: @escaping () -> Void) {
        self.model = model
        self.onDismiss = onDismiss
        _instruction = State(initialValue: model.project.overlayPrompt ?? Self.defaultInstruction)
        _showsAfter = State(initialValue: model.overlayURL != nil)
    }

    private var previewWidth: CGFloat {
        // Leave room for the editor, footer and status text on shorter screens.
        min(636, max(100, ((NSScreen.main?.visibleFrame.height ?? 900) - 560) * 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Overlay").font(.title2.bold())
            Text("Adjust the whole panorama with AI.").foregroundStyle(.secondary)
            Picker("Comparison", selection: $showsAfter) {
                Text("Before").tag(false)
                Text("After").tag(true).disabled(after == nil)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .frame(maxWidth: .infinity)
            OverlayComparisonPane(
                title: showsAfter ? "After" : "Before",
                image: showsAfter ? after : before,
                width: previewWidth
            ).frame(maxWidth: .infinity)
            HStack {
                Text("Instruction").font(.headline)
                Button { instruction = Self.defaultInstruction } label: {
                    Image(systemName: "arrow.counterclockwise")
                }.buttonStyle(.plain).help("Restore default instruction").disabled(isWorking)
                Spacer()
            }
            TextEditor(text: $instruction)
                .font(.body).scrollContentBackground(.hidden)
                .padding(6).frame(height: 144)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .disabled(isWorking)
            Text("The panorama is sent to OpenAI. API usage is billed separately.")
                .font(.caption).foregroundStyle(.secondary)
            if let generatedSize {
                Text("AI: \(Int(generatedSize.width)) × \(Int(generatedSize.height)) pixels. Saved without resizing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            HStack {
                Button("Cancel", role: .cancel) { generation?.cancel(); onDismiss() }
                Spacer()
                Button("API Key…") { showsKey = true }.disabled(isWorking)
                if isWorking {
                    ProgressView().controlSize(.small)
                    Button("Stop") { generation?.cancel() }
                } else {
                    Button("Generate") { generate() }
                        .disabled(before == nil || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Apply") { apply() }.buttonStyle(.borderedProminent)
                        .disabled(generatedData == nil)
                }
            }
        }.padding(22)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(isWorking)
        .task {
            let baseURL = model.basePanoramaURL
            let overlayURL = model.overlayURL
            let images = await Task.detached(priority: .userInitiated) {
                (baseURL.flatMap { OverlayImageIO.read(url: $0) },
                 overlayURL.flatMap { OverlayImageIO.read(url: $0) })
            }.value
            guard !Task.isCancelled else { return }
            before = images.0
            after = images.1
        }
        .onChange(of: instruction) { generatedData = nil }
        .onDisappear { generation?.cancel() }
        .sheet(isPresented: $showsKey) { OpenAIAPIKeySheet { showsKey = false } }
    }

    private func generate() {
        guard let apiKey = keyStore.load() else { showsKey = true; return }
        guard let sourceURL = model.basePanoramaURL else { return }
        let prompt = instruction
        errorMessage = nil
        isWorking = true
        generation = Task {
            defer { isWorking = false }
            do {
                let input = try await Task.detached(priority: .userInitiated) {
                    try OverlayImageIO.prepareInput(url: sourceURL)
                }.value
                let result = try await OpenAIImageEditService(apiKey: apiKey).edit(
                    imageData: input.data, filename: "panorama.png",
                    prompt: "This is a full equirectangular 360-degree panorama. Preserve its exact 2:1 projection, framing and continuous left/right boundary. Do not crop, rotate or reframe. Follow this instruction: " + prompt,
                    size: input.width, height: input.height
                )
                try Task.checkCancellation()
                let image = try OverlayImageIO.matchingImage(
                    data: result, width: input.width, height: input.height
                )
                guard model.basePanoramaURL == sourceURL else { throw AIRetouchError.panoramaUnavailable }
                generatedData = result
                generatedSize = CGSize(width: image.width, height: image.height)
                after = image
                showsAfter = true
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func apply() {
        guard let generatedData, let sourceURL = model.basePanoramaURL else { return }
        do {
            let original = try OverlayImageIO.dimensions(url: sourceURL)
            let dimensions = try OverlayImageIO.editDimensions(width: original.0, height: original.1)
            _ = try OverlayImageIO.matchingImage(
                data: generatedData, width: dimensions.0, height: dimensions.1
            )
            try model.applyOverlay(generatedData, prompt: instruction)
            onDismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct OverlayComparisonPane: View {
    let title: String
    let image: CGImage?
    let width: CGFloat
    var placeholder = "The AI result appears here."

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Text(placeholder).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: width / 2)
        .clipped()
        .accessibilityIdentifier("overlay-\(title.lowercased())-2to1")
    }
}

private enum OverlayImageIO {
    enum Failure: LocalizedError {
        case unreadable
        case invalidPanorama
        case wrongDimensions(width: Int, height: Int, expectedWidth: Int, expectedHeight: Int)
        var errorDescription: String? {
            switch self {
            case .unreadable: "The panorama image could not be read."
            case .invalidPanorama: "The panorama must have a 2:1 aspect ratio and be at least 32 × 16 pixels."
            case let .wrongDimensions(width, height, expectedWidth, expectedHeight):
                "OpenAI returned \(width) × \(height) pixels; the requested size is \(expectedWidth) × \(expectedHeight). The image has not been resized or applied."
            }
        }
    }
    static func read(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
    static func read(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    static func dimensions(url: URL) throws -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw Failure.unreadable }
        return (width, height)
    }
    static func matchingImage(data: Data, width: Int, height: Int) throws -> CGImage {
        guard let image = read(data: data) else { throw Failure.unreadable }
        guard image.width == width, image.height == height else {
            throw Failure.wrongDimensions(
                width: image.width, height: image.height,
                expectedWidth: width, expectedHeight: height
            )
        }
        return image
    }

    static func editDimensions(width: Int, height: Int) throws -> (Int, Int) {
        guard height >= 16, width == height * 2 else { throw Failure.invalidPanorama }
        let alignedHeight = height / 16 * 16
        return (alignedHeight * 2, alignedHeight)
    }

    static func prepareInput(url: URL) throws -> (data: Data, width: Int, height: Int) {
        let data = try Data(contentsOf: url)
        let original = try dimensions(url: url)
        let (width, height) = try editDimensions(width: original.0, height: original.1)
        guard width != original.0 || height != original.1 else { return (data, width, height) }
        guard let image = read(data: data),
              let context = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.unreadable }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = context.makeImage() else { throw Failure.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.unreadable
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return (output as Data, width, height)
    }
}
