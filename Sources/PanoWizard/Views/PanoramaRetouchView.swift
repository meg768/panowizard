import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum RetouchPatchDialogKind {
    case ai
    case manual
}

struct RetouchPatchPresentation: Identifiable {
    let id = UUID()
    let kind: RetouchPatchDialogKind
    let viewpoint: PanoramaViewpoint
}

struct PanoramaRetouchView: View {
    @Bindable var model: AppModel
    let projectDirectoryURL: URL?
    let presentPatch: (RetouchPatchPresentation) -> Void

    var body: some View {
        if model.stitchedResultURL != nil {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Button {
                            presentPatch(RetouchPatchPresentation(
                                kind: .manual,
                                viewpoint: model.panoramaViewpoint
                            ))
                        } label: {
                            Label(
                                "Add manual patch",
                                systemImage: "paintbrush"
                            )
                        }
                        .accessibilityIdentifier("add-manual-patch")

                        Button {
                            presentPatch(RetouchPatchPresentation(
                                kind: .ai,
                                viewpoint: model.panoramaViewpoint
                            ))
                        } label: {
                            Label(
                                "Add AI patch",
                                systemImage: "wand.and.sparkles"
                            )
                        }
                        .accessibilityIdentifier("add-ai-patch")
                    }
                    .buttonStyle(WorkspaceToolbarPillStyle())
                    .disabled(model.phase != .ready)

                    Text(
                        "New patches open at the direction and zoom currently "
                            + "shown in Preview. Pan or zoom directly in the "
                            + "patch dialog to choose the exact area."
                    )
                    .foregroundStyle(.secondary)
                }

                Section("Patches") {
                    if model.retouchPatches.isEmpty {
                        Text("No retouch patches")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(
                            Array(model.retouchPatches.reversed())
                        ) { patch in
                            retouchPatchRow(patch)
                        }
                    }
                }

                Section {
                    Text(
                        "Patches are stored separately and do not alter "
                            + "source images, masks, or panorama geometry."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView {
                Label("No Panorama to Retouch", systemImage: "paintbrush.pointed")
            } description: {
                Text("Create the panorama before adding retouch patches.")
            } actions: {
                Button("Create") { model.stitch() }
                    .buttonStyle(WorkspaceToolbarPillStyle())
                    .disabled(!model.canStitch)
            }
        }
    }

    private func retouchPatchRow(_ patch: RetouchPatch) -> some View {
        HStack(spacing: 12) {
            if let url = model.retouchPatchURLs[patch.id],
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Button {
                model.showRetouchPatch(patch)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(patch.kind.displayName)
                    Text(patch.isEnabled ? "Active" : "Hidden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Toggle("Enabled", isOn: Binding(
                get: { patch.isEnabled },
                set: { _ in model.toggleRetouchPatch(patch.id) }
            ))
            .labelsHidden()

            Button("Delete Patch", systemImage: "trash", role: .destructive) {
                model.removeRetouchPatch(patch.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }
}

struct ManualRetouchSheet: View {
    @Bindable var model: AppModel
    let projectDirectoryURL: URL?
    let onDismiss: () -> Void

    @State private var viewpoint: PanoramaViewpoint
    @State private var source: AIRetouchSource?
    @State private var importedURL: URL?
    @State private var errorMessage: String?
    @State private var isWorking = false

    init(
        model: AppModel,
        viewpoint: PanoramaViewpoint,
        projectDirectoryURL: URL?,
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.projectDirectoryURL = projectDirectoryURL
        self.onDismiss = onDismiss
        _viewpoint = State(initialValue: viewpoint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manual Retouch Patch")
                    .font(.title2.bold())
                Text(
                    "Export this view, edit it externally, then import the "
                        + "finished 2048 × 2048 PNG."
                )
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                AIRetouchImagePane(
                    title: "Before",
                    footer: "Drag to pan · scroll or pinch to zoom"
                ) {
                    if let panoramaURL = model.currentPanoramaURL {
                        RetouchPatchPanoramaViewport(
                            url: panoramaURL,
                            initialViewpoint: viewpoint,
                            onViewpointChange: handleViewpointChange
                        )
                    } else {
                        AIRetouchImagePlaceholder(
                            text: "The panorama is unavailable."
                        )
                    }
                } trailing: { EmptyView() }

                AIRetouchImagePane(
                    title: "After",
                    footer: "Leave unchanged image content around edited areas."
                ) {
                    if let importedURL {
                        AIRetouchImageViewport(
                            url: importedURL,
                            maskData: nil,
                            interaction: .pan,
                            isEnabled: true,
                            onMaskChange: { _ in },
                            onUndo: {}
                        )
                    } else {
                        AIRetouchImagePlaceholder(
                            text: "The imported patch appears here."
                        )
                    }
                } trailing: { EmptyView() }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel", role: .cancel, action: onDismiss)
                Spacer()
                Button("Export…") { Task { await exportSource() } }
                    .disabled(isWorking)
                Button("Import…") { importPatch() }
                    .disabled(source == nil || isWorking)
                Button("Apply") { applyPatch() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(importedURL == nil || isWorking)
            }
        }
        .padding(22)
        .frame(width: 780)
        .onDisappear {
            if let source { model.discardRetouchPatchSource(source) }
        }
    }

    private func handleViewpointChange(_ newViewpoint: PanoramaViewpoint) {
        guard viewpoint != newViewpoint else { return }
        viewpoint = newViewpoint
        if let source { model.discardRetouchPatchSource(source) }
        source = nil
        importedURL = nil
        errorMessage = nil
    }

    private func loadSource() async -> AIRetouchSource? {
        if let source { return source }
        isWorking = true
        defer { isWorking = false }
        do {
            let loaded = try await model.createRetouchPatchSource(at: viewpoint)
            source = loaded
            return loaded
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func exportSource() async {
        guard let source = await loadSource() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = projectDirectoryURL
        panel.nameFieldStringValue = "patch.png"
        panel.title = "Export Retouch Patch"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(contentsOf: source.sourceURL).write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPatch() {
        guard let source else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = projectDirectoryURL
        panel.nameFieldStringValue = "patch.png"
        panel.title = "Import Retouch Patch"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let destination = source.directoryURL.appending(path: "imported.png")
        do {
            try RetouchPatchService().prepareImportedPatch(
                from: url,
                to: destination
            )
            importedURL = destination
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyPatch() {
        guard let importedURL, let source else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try model.applyManualRetouchPatch(
                from: importedURL,
                viewpoint: source.viewpoint
            )
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AIRetouchSheet: View {
    @Bindable var model: AppModel
    let onDismiss: () -> Void

    @State private var viewpoint: PanoramaViewpoint
    @State private var prompt: String
    @State private var source: AIRetouchSource?
    @State private var sourceTask: Task<Void, Never>?
    @State private var sourceRequestID: UUID?
    @State private var preview: AIRetouchPreview?
    @State private var maskData: Data?
    @State private var maskHistory: [Data?] = []
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var isMaskMode = false
    @State private var isPreparingSource = false
    @State private var isWorking = false
    @State private var storedAPIKey: String?
    @State private var isAPIKeySheetPresented = false
    @State private var isMissingAPIKeyAlertPresented = false

    private let keyStore = OpenAIAPIKeyStore()

    init(
        model: AppModel,
        viewpoint: PanoramaViewpoint,
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.onDismiss = onDismiss
        _viewpoint = State(initialValue: viewpoint)
        _prompt = State(initialValue: Self.defaultPrompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Retouch Patch")
                    .font(.title2.bold())
                Text(
                    "The image is sent to OpenAI. No retouch is activated "
                        + "until you choose Apply."
                )
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                AIRetouchImagePane(
                    title: "Before",
                    footer: isMaskMode
                        ? "Drag to paint · ⌥-drag to erase · ⌘Z to undo · "
                            + "Clear Mask to navigate"
                        : "Drag to pan · scroll or pinch to zoom"
                ) {
                    if let panoramaURL = model.currentPanoramaURL {
                        ZStack {
                            RetouchPatchPanoramaViewport(
                                url: panoramaURL,
                                initialViewpoint: viewpoint,
                                onViewpointChange: handleViewpointChange,
                                maskData: maskData,
                                isMaskEditing: isMaskMode
                                    && !isPreparingSource
                                    && !isWorking,
                                onMaskChange: applyMaskChange
                            )
                            .allowsHitTesting(
                                !isPreparingSource && !isWorking
                            )

                            if isPreparingSource {
                                ProgressView()
                                    .controlSize(.regular)
                            }
                        }
                    } else {
                        AIRetouchImagePlaceholder(
                            text: "The panorama is unavailable."
                        )
                    }
                } trailing: {
                    if isMaskMode {
                        Button("Clear Mask", role: .destructive) {
                            clearMask()
                        }
                        .disabled(isWorking)
                        .accessibilityIdentifier("clear-ai-retouch-mask")
                    } else {
                        Button {
                            beginMaskMode()
                        } label: {
                            Label("Mask", systemImage: "paintbrush")
                        }
                        .disabled(isWorking)
                        .accessibilityIdentifier("activate-ai-retouch-mask")
                    }
                }
                .background {
                    AIRetouchMaskUndoMonitor(onUndo: undoMaskChange)
                }

                AIRetouchImagePane(
                    title: "After",
                    footer: "Drag to pan · scroll or pinch to zoom"
                ) {
                    if let afterURL {
                        AIRetouchImageViewport(
                            url: afterURL,
                            maskData: nil,
                            interaction: .pan,
                            isEnabled: true,
                            onMaskChange: { _ in },
                            onUndo: {}
                        )
                        .id("ai-retouch-after-viewport")
                    } else {
                        AIRetouchImagePlaceholder(
                            text: "The AI result appears here after retouching."
                        )
                    }
                } trailing: {
                    EmptyView()
                }
            }

            GroupBox {
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 82, maxHeight: 110)
                    .padding(6)
            } label: {
                HStack(spacing: 5) {
                    Text("Instruction")
                    Button {
                        restoreDefaultPrompt()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Restore default instruction")
                    .accessibilityLabel("Restore default instruction")
                    .disabled(!canRestoreDefaultPrompt)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    cancelAndDismiss()
                }
                Spacer()
                Button(
                    storedAPIKey == nil
                        ? "Create API Key…"
                        : "Change API Key…"
                ) {
                    isAPIKeySheetPresented = true
                }
                if preview != nil {
                    Button("Try Again") {
                        generate()
                    }
                    .disabled(isWorking || !canGenerate)

                    Button("Apply") {
                        applyPreview()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
                } else {
                    Button("AI Retouch") {
                        generate()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || !canGenerate)
                }
            }
        }
        .padding(22)
        .frame(width: 780)
        .task {
            storedAPIKey = keyStore.load()
        }
        .sheet(isPresented: $isAPIKeySheetPresented) {
            OpenAIAPIKeySheet {
                storedAPIKey = keyStore.load()
            }
        }
        .sheet(isPresented: $isWorking) {
            AIRetouchProgressSheet(onCancel: cancelGeneration)
        }
        .alert(
            "API Key Missing",
            isPresented: $isMissingAPIKeyAlertPresented
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "You need to create an OpenAI API key before you can use "
                    + "AI retouching."
            )
        }
        .onDisappear {
            sourceTask?.cancel()
            generationTask?.cancel()
            if let preview {
                model.discardAIRetouchPreview(preview)
            }
            if let source {
                model.discardRetouchPatchSource(source)
            }
        }
    }

    private var canGenerate: Bool {
        isMaskMode
            && source != nil
            && maskData != nil
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var afterURL: URL? {
        preview?.compositedURL
    }

    private var canRestoreDefaultPrompt: Bool {
        prompt != Self.defaultPrompt
    }

    private func restoreDefaultPrompt() {
        prompt = Self.defaultPrompt
    }

    private func handleViewpointChange(_ newViewpoint: PanoramaViewpoint) {
        guard !isMaskMode, viewpoint != newViewpoint else { return }
        viewpoint = newViewpoint
    }

    private func beginMaskMode() {
        guard !isMaskMode, !isWorking else { return }
        isMaskMode = true
        isPreparingSource = true
        maskData = nil
        maskHistory = []
        errorMessage = nil
        invalidatePreview()

        sourceTask?.cancel()
        if let source { model.discardRetouchPatchSource(source) }
        source = nil

        let capturedViewpoint = viewpoint
        let requestID = UUID()
        sourceRequestID = requestID
        sourceTask = Task {
            do {
                let loadedSource = try await model.createRetouchPatchSource(
                    at: capturedViewpoint
                )
                guard !Task.isCancelled,
                      sourceRequestID == requestID,
                      isMaskMode else {
                    model.discardRetouchPatchSource(loadedSource)
                    return
                }
                source = loadedSource
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, sourceRequestID == requestID else {
                    return
                }
                errorMessage = error.localizedDescription
            }
            if sourceRequestID == requestID {
                isPreparingSource = false
            }
        }
    }

    private func generate() {
        guard let apiKey = keyStore.load() else {
            storedAPIKey = nil
            isMissingAPIKeyAlertPresented = true
            return
        }
        errorMessage = nil
        guard let source else {
            errorMessage = AIRetouchError.panoramaUnavailable.localizedDescription
            return
        }

        isWorking = true
        let oldPreview = preview
        generationTask?.cancel()
        generationTask = Task {
            defer { isWorking = false }
            do {
                let newPreview = try await model.createAIRetouchPreview(
                    source: source,
                    maskData: maskData,
                    prompt: prompt,
                    apiKey: apiKey
                )
                guard !Task.isCancelled else {
                    model.discardAIRetouchPreview(newPreview)
                    return
                }
                if let oldPreview {
                    model.discardAIRetouchPreview(oldPreview)
                }
                preview = newPreview
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyPreview() {
        guard let preview, let maskData else { return }
        do {
            try model.applyAIRetouchPreview(
                preview,
                prompt: prompt,
                maskData: maskData
            )
            model.discardAIRetouchPreview(preview)
            self.preview = nil
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelAndDismiss() {
        generationTask?.cancel()
        if let preview {
            model.discardAIRetouchPreview(preview)
            self.preview = nil
        }
        onDismiss()
    }

    private func cancelGeneration() {
        generationTask?.cancel()
    }

    private func applyMaskChange(_ newMaskData: Data?) {
        guard isMaskMode, !isWorking, newMaskData != maskData else { return }
        maskHistory.append(maskData)
        maskData = newMaskData
        invalidatePreview()
    }

    private func undoMaskChange() {
        guard isMaskMode,
              !isWorking,
              let previous = maskHistory.popLast() else { return }
        maskData = previous
        invalidatePreview()
    }

    private func clearMask() {
        guard isMaskMode, !isWorking else { return }
        sourceTask?.cancel()
        sourceTask = nil
        sourceRequestID = nil
        isPreparingSource = false
        if let source { model.discardRetouchPatchSource(source) }
        source = nil
        maskData = nil
        maskHistory = []
        invalidatePreview()
        errorMessage = nil
        isMaskMode = false
    }

    private func invalidatePreview() {
        guard let preview else { return }
        model.discardAIRetouchPreview(preview)
        self.preview = nil
    }

    private static let defaultPrompt = """
            This is a flat view of part of a 360° panorama. The masked area has been removed and must be reconstructed.

            Fill the missing area photorealistically based on the surrounding image. Continue existing structures, lines, patterns, seams, and textures with correct geometry and perspective.

            The reconstruction must blend seamlessly with the surrounding original image. Locally match exposure, brightness, hue, white balance, contrast, sharpness, texture, and noise so that no visible boundary or tonal edge appears around the reconstructed area.

            The transition between reconstructed and original image content must be smooth and gradual. Avoid a uniformly bounded or mask-shaped change in light or color.

            Preserve the image's existing geometry and perspective. Do not alter objects or structures that do not need to be reconstructed to fill the missing area.

            Do not apply global image processing. All color, tone, and exposure adjustments must be local and limited to what is required to make the reconstruction invisible.
            """

}

private struct RetouchPatchPanoramaViewport: View {
    let url: URL
    let initialViewpoint: PanoramaViewpoint
    let onViewpointChange: (PanoramaViewpoint) -> Void
    var maskData: Data? = nil
    var isMaskEditing = false
    var onMaskChange: (Data?) -> Void = { _ in }

    var body: some View {
        SphericalPanoramaView(
            url: url,
            overlayURL: nil,
            zenithOverlayURL: nil,
            nadirRetouchURL: nil,
            zenithRetouchURL: nil,
            adjustments: .neutral,
            initialViewpoint: initialViewpoint,
            onViewpointChange: onViewpointChange,
            maskData: maskData,
            isMaskEditing: isMaskEditing,
            onMaskChange: onMaskChange,
            addsWorkspacePadding: false
        )
    }
}

private struct AIRetouchProgressSheet: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.small)

            VStack(spacing: 4) {
                Text("OpenAI is retouching the image…")
                    .font(.headline)
                Text("This may take up to two minutes.")
                    .foregroundStyle(.secondary)
            }

            Button("Cancel", role: .cancel, action: onCancel)
        }
        .padding(24)
        .frame(width: 320)
        .interactiveDismissDisabled()
    }
}

private struct AIRetouchImagePane<Content: View, Trailing: View>: View {
    let title: String
    let footer: String
    let content: Content
    let trailing: Trailing

    init(
        title: String,
        footer: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer()
                trailing
            }
            .frame(height: 24)

            content
                .frame(width: 360, height: 360)
                .background(
                    .black.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
        }
        .frame(width: 360)
    }
}

private struct AIRetouchImagePlaceholder: View {
    let text: String
    var showsProgress = false

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum AIRetouchImageInteraction {
    case mask
    case pan
}

private struct AIRetouchImageViewport: NSViewRepresentable {
    let url: URL
    let maskData: Data?
    let interaction: AIRetouchImageInteraction
    let isEnabled: Bool
    let onMaskChange: (Data?) -> Void
    let onUndo: () -> Void

    func makeNSView(context: Context) -> AIRetouchScrollView {
        AIRetouchScrollView()
    }

    func updateNSView(_ scrollView: AIRetouchScrollView, context: Context) {
        scrollView.configure(
            url: url,
            maskData: maskData,
            interaction: interaction,
            isEnabled: isEnabled,
            onMaskChange: onMaskChange,
            onUndo: onUndo
        )
    }
}

private final class AIRetouchScrollView: NSScrollView {
    private let imageView = AIRetouchImageDocumentView()
    private var imageURL: URL?
    private var displayedMaskData: Data?
    private var needsInitialFit = false
    private var hasCompletedInitialFit = false
    private var fitGeneration = 0
    private var hasUserAdjustedViewport = false
    private var isUpdatingFit = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = AIRetouchCenteredClipView()
        drawsBackground = true
        backgroundColor = .windowBackgroundColor
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.01
        maxMagnification = 8
        documentView = imageView
        imageView.viewport = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil,
              imageURL != nil,
              !hasCompletedInitialFit else { return }
        requestFit()
    }

    override func layout() {
        super.layout()
        guard !isUpdatingFit, window != nil, needsInitialFit else { return }
        isUpdatingFit = true
        let didUpdate = performInitialFit()
        isUpdatingFit = false
        guard didUpdate else { return }
        needsInitialFit = false
        hasCompletedInitialFit = true
    }

    override func scrollWheel(with event: NSEvent) {
        let zoomDelta = ImageSurfaceScroll.dominantDelta(for: event)
        guard abs(zoomDelta) > 0.01, let documentView else { return }
        hasUserAdjustedViewport = true
        let anchor = documentView.convert(event.locationInWindow, from: nil)
        let target = min(max(
            magnification * exp(-zoomDelta * 0.008),
            minMagnification
        ), maxMagnification)
        guard abs(target - magnification) > 0.000_001 else { return }
        setMagnification(target, centeredAt: anchor)
        imageView.needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        hasUserAdjustedViewport = true
        super.magnify(with: event)
        imageView.needsDisplay = true
    }

    func configure(
        url: URL,
        maskData: Data?,
        interaction: AIRetouchImageInteraction,
        isEnabled: Bool,
        onMaskChange: @escaping (Data?) -> Void,
        onUndo: @escaping () -> Void
    ) {
        let isFirstImage = imageURL == nil
        let imageChanged = imageURL != url
        if imageChanged {
            imageURL = url
            imageView.image = Self.loadImage(url: url)
            if let image = imageView.image {
                imageView.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: image.width,
                    height: image.height
                )
            }
        }
        if isFirstImage {
            requestFit()
        }
        if displayedMaskData != maskData {
            displayedMaskData = maskData
            imageView.maskImage = Self.loadImage(data: maskData)
        }
        imageView.maskData = maskData
        imageView.interaction = interaction
        imageView.isPaintingEnabled = isEnabled
        imageView.onMaskChange = onMaskChange
        imageView.onUndo = onUndo
        imageView.needsDisplay = true
    }

    func beginUserNavigation() {
        hasUserAdjustedViewport = true
    }

    private func requestFit() {
        fitGeneration += 1
        hasUserAdjustedViewport = false
        needsInitialFit = true
        needsLayout = true
        scheduleInitialFit(for: fitGeneration, remainingPasses: 3)
    }

    private func scheduleInitialFit(
        for generation: Int,
        remainingPasses: Int
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.fitGeneration == generation,
                  self.window != nil,
                  !self.hasUserAdjustedViewport else { return }
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            if !self.isUpdatingFit {
                self.isUpdatingFit = true
                let didUpdate = self.performInitialFit()
                self.isUpdatingFit = false
                if didUpdate {
                    self.needsInitialFit = false
                    self.hasCompletedInitialFit = true
                }
            }
            if remainingPasses > 1 {
                self.scheduleInitialFit(
                    for: generation,
                    remainingPasses: remainingPasses - 1
                )
            }
        }
    }

    @discardableResult
    private func performInitialFit() -> Bool {
        guard imageView.bounds.width > 0,
              imageView.bounds.height > 0,
              contentView.frame.width > 0,
              contentView.frame.height > 0 else { return false }
        let newFit = min(
            contentView.frame.width / imageView.bounds.width,
            contentView.frame.height / imageView.bounds.height
        )
        guard newFit.isFinite, newFit > 0 else { return false }
        let center = CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        let newMaximum = newFit * 8
        if newFit > maxMagnification {
            maxMagnification = newMaximum
            minMagnification = newFit
        } else {
            minMagnification = newFit
            maxMagnification = newMaximum
        }
        setMagnification(newFit, centeredAt: center)
        imageView.needsDisplay = true
        return abs(magnification - newFit) < 0.000_001
    }

    private static func loadImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func loadImage(data: Data?) -> CGImage? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

private struct AIRetouchMaskUndoMonitor: NSViewRepresentable {
    let onUndo: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onUndo: onUndo)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onUndo = onUndo
        context.coordinator.windowNumber = view.window?.windowNumber
        context.coordinator.hitRectInWindow = view.convert(view.bounds, to: nil)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onUndo: () -> Void
        var windowNumber: Int?
        var hitRectInWindow = CGRect.zero
        private var isActive = false
        private var monitor: Any?

        init(onUndo: @escaping () -> Void) {
            self.onUndo = onUndo
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self, self.windowNumber == event.windowNumber else {
                    return event
                }
                if event.type == .leftMouseDown {
                    self.isActive = self.hitRectInWindow.contains(
                        event.locationInWindow
                    )
                    return event
                }
                guard self.isActive,
                      event.modifierFlags.contains(.command),
                      event.charactersIgnoringModifiers?.lowercased() == "z"
                else { return event }
                self.onUndo()
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private final class AIRetouchCenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return bounds }
        if bounds.width > documentView.frame.width {
            bounds.origin.x = (documentView.frame.width - bounds.width) / 2
        }
        if bounds.height > documentView.frame.height {
            bounds.origin.y = (documentView.frame.height - bounds.height) / 2
        }
        return bounds
    }
}

private final class AIRetouchImageDocumentView: NSView {
    private static let screenBrushDiameter: CGFloat = 48
    private static let transparentCursor = NSCursor(
        image: NSImage(size: CGSize(width: 1, height: 1)),
        hotSpot: .zero
    )

    weak var viewport: AIRetouchScrollView?
    var image: CGImage?
    var maskImage: CGImage?
    var maskData: Data?
    var interaction = AIRetouchImageInteraction.pan
    var isPaintingEnabled = true
    var onMaskChange: (Data?) -> Void = { _ in }
    var onUndo: () -> Void = {}

    private var activeStroke: [CGPoint] = []
    private var hoverPoint: CGPoint?
    private var isErasingStroke = false
    private var panOrigin: CGPoint?
    private var panStart: CGPoint?
    private var trackingAreaReference: NSTrackingArea?
    private var modifierMonitor: Any?
    private var modifierInteraction = ImageSurfaceInteraction.navigate {
        didSet {
            guard modifierInteraction != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { interaction == .mask }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeModifierMonitor()
        } else {
            installModifierMonitor()
        }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor = if interaction == .mask,
                                  modifierInteraction != .navigate,
                                  isPaintingEnabled {
            Self.transparentCursor
        } else {
            .openHand
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseMoved,
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect
            ],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaReference = area
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        draw(image, fraction: 1, operation: .copy)
        if let maskImage {
            draw(
                maskImage,
                fraction: CGFloat(MaskOverlayAppearance.committedOpacity),
                operation: .sourceOver
            )
        }
        drawActiveStroke()
        drawBrushCursor()
    }

    override func mouseDown(with event: NSEvent) {
        window?.acceptsMouseMovedEvents = true
        updateModifierInteraction(event.modifierFlags)
        if interaction == .mask,
           modifierInteraction != .navigate,
           isPaintingEnabled {
            window?.makeFirstResponder(self)
            isErasingStroke = modifierInteraction == .remove
            activeStroke = [clampedPoint(for: event)]
            needsDisplay = true
        } else if let viewport {
            viewport.beginUserNavigation()
            panOrigin = viewport.contentView.bounds.origin
            panStart = event.locationInWindow
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if !activeStroke.isEmpty {
            let point = clampedPoint(for: event)
            if activeStroke.last != point {
                activeStroke.append(point)
                hoverPoint = point
                needsDisplay = true
            }
        } else {
            pan(to: event.locationInWindow)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            activeStroke = []
            isErasingStroke = false
            if panOrigin != nil { NSCursor.pop() }
            panOrigin = nil
            panStart = nil
            needsDisplay = true
        }
        guard isPaintingEnabled,
              let image,
              !activeStroke.isEmpty else { return }
        let points = activeStroke.map {
            MaskPoint(
                x: $0.x / CGFloat(image.width),
                y: $0.y / CGFloat(image.height)
            )
        }
        let radius = Self.screenBrushDiameter
            / 2 / max(viewport?.magnification ?? 1, 0.000_001)
        onMaskChange(SourceMaskRasterizer.applying(
            stroke: points,
            radius: radius,
            erasing: isErasingStroke,
            to: maskData,
            width: image.width,
            height: image.height
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard interaction == .mask else { return }
        updateModifierInteraction(event.modifierFlags)
        hoverPoint = clampedPoint(for: event)
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        guard interaction == .mask else { return }
        updateModifierInteraction(event.modifierFlags)
        hoverPoint = clampedPoint(for: event)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if interaction == .mask,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            onUndo()
            return
        }
        super.keyDown(with: event)
    }

    private func pan(to location: CGPoint) {
        guard let viewport, let panOrigin, let panStart else { return }
        let scale = max(viewport.magnification, 0.000_001)
        let proposed = CGRect(
            origin: CGPoint(
                x: panOrigin.x - (location.x - panStart.x) / scale,
                y: panOrigin.y + (location.y - panStart.y) / scale
            ),
            size: viewport.contentView.bounds.size
        )
        let constrained = viewport.contentView.constrainBoundsRect(proposed)
        viewport.contentView.scroll(to: constrained.origin)
        viewport.reflectScrolledClipView(viewport.contentView)
    }

    private func installModifierMonitor() {
        guard modifierMonitor == nil else { return }
        modifierMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            guard let self,
                  event.window == nil || event.window === self.window else {
                return event
            }
            self.updateModifierInteraction(event.modifierFlags)
            return event
        }
    }

    private func removeModifierMonitor() {
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
        modifierMonitor = nil
    }

    private func updateModifierInteraction(
        _ flags: NSEvent.ModifierFlags
    ) {
        modifierInteraction = ImageSurfaceInteraction(modifierFlags: flags)
    }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )
    }

    private func draw(
        _ image: CGImage,
        fraction: CGFloat,
        operation: NSCompositingOperation
    ) {
        let size = CGSize(width: image.width, height: image.height)
        NSImage(cgImage: image, size: size).draw(
            in: bounds,
            from: CGRect(origin: .zero, size: size),
            operation: operation,
            fraction: fraction,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawActiveStroke() {
        guard interaction == .mask, !activeStroke.isEmpty else { return }
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = sourceBrushDiameter
        path.move(to: activeStroke[0])
        activeStroke.dropFirst().forEach { path.line(to: $0) }
        if activeStroke.count == 1 {
            path.appendOval(in: CGRect(
                x: activeStroke[0].x - sourceBrushDiameter / 2,
                y: activeStroke[0].y - sourceBrushDiameter / 2,
                width: sourceBrushDiameter,
                height: sourceBrushDiameter
            ))
            (isErasingStroke
                ? NSColor.white.withAlphaComponent(0.72)
                : NSColor(
                    red: 1,
                    green: 0.12,
                    blue: 0.08,
                    alpha: CGFloat(MaskOverlayAppearance.activeStrokeOpacity)
                )).setFill()
            path.fill()
        } else {
            (isErasingStroke
                ? NSColor.white.withAlphaComponent(0.72)
                : NSColor(
                    red: 1,
                    green: 0.12,
                    blue: 0.08,
                    alpha: CGFloat(MaskOverlayAppearance.activeStrokeOpacity)
                )).setStroke()
            path.stroke()
        }
    }

    private func drawBrushCursor() {
        guard interaction == .mask,
              modifierInteraction != .navigate,
              isPaintingEnabled,
              let hoverPoint else { return }
        let radius = sourceBrushDiameter / 2
        let cursor = NSBezierPath(ovalIn: CGRect(
            x: hoverPoint.x - radius,
            y: hoverPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        cursor.lineWidth = 3 / max(viewport?.magnification ?? 1, 0.000_001)
        NSColor.black.withAlphaComponent(0.85).setStroke()
        cursor.stroke()
        cursor.lineWidth = 1 / max(viewport?.magnification ?? 1, 0.000_001)
        NSColor.white.setStroke()
        cursor.stroke()
        guard modifierInteraction == .remove else { return }
        let slash = NSBezierPath()
        let offset = radius * 0.7
        slash.move(to: CGPoint(
            x: hoverPoint.x - offset,
            y: hoverPoint.y - offset
        ))
        slash.line(to: CGPoint(
            x: hoverPoint.x + offset,
            y: hoverPoint.y + offset
        ))
        slash.lineWidth = 3 / max(
            viewport?.magnification ?? 1,
            0.000_001
        )
        NSColor.black.withAlphaComponent(0.85).setStroke()
        slash.stroke()
        slash.lineWidth = 1 / max(
            viewport?.magnification ?? 1,
            0.000_001
        )
        NSColor.white.setStroke()
        slash.stroke()
    }

    private var sourceBrushDiameter: CGFloat {
        Self.screenBrushDiameter
            / max(viewport?.magnification ?? 1, 0.000_001)
    }
}
