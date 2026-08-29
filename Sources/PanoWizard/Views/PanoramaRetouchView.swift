import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PanoramaRetouchController {
    func exportPlate(
        model: AppModel,
        pole: PanoramaPole,
        projectDirectoryURL: URL?
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = projectDirectoryURL
        panel.nameFieldStringValue = pole == .nadir ? "nadir.png" : "zenit.png"
        panel.title = "Exportera retusch för \(pole.displayName.lowercased())"
        panel.prompt = "Exportera"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportRetouchPlate(for: pole, to: url)
    }

    func importPlate(model: AppModel, pole: PanoramaPole) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Importera retusch för \(pole.displayName.lowercased())"
        panel.prompt = "Importera"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importRetouchPlate(for: pole, from: url)
    }
}

struct PanoramaRetouchView: View {
    @Bindable var model: AppModel
    let projectDirectoryURL: URL?
    let controller: PanoramaRetouchController
    let onAIRetouch: (PanoramaPole) -> Void

    var body: some View {
        if model.stitchedResultURL != nil {
            Form {
                poleSection(.nadir)
                poleSection(.zenith)

                Section {
                    Text(
                        "Retuscher sparas separat i projektet och ändrar inte "
                            + "källbilder, kontrollpunkter eller panoramageometri."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView {
                Label(
                    "Inget panorama att retuschera",
                    systemImage: "paintbrush.pointed"
                )
            } description: {
                Text("Generera panoramat för att skapa plana polsidor.")
            } actions: {
                Button("Generera") {
                    model.stitch()
                }
                .buttonStyle(WorkspaceToolbarPillStyle())
                .disabled(!model.canStitch)
            }
        }
    }

    @ViewBuilder
    private func poleSection(_ pole: PanoramaPole) -> some View {
        Section(pole.displayName) {
            LabeledContent(
                "Format",
                value: "PNG · 2048 × 2048 px · 90° kubsida"
            )
            LabeledContent(
                "Status",
                value: model.retouchURL(for: pole) == nil
                    ? "Ingen retusch"
                    : "Retusch aktiv"
            )

            HStack(spacing: 8) {
                Button {
                    onAIRetouch(pole)
                } label: {
                    Label("AI-retuschera…", systemImage: "wand.and.sparkles")
                }

                Button {
                    controller.exportPlate(
                        model: model,
                        pole: pole,
                        projectDirectoryURL: projectDirectoryURL
                    )
                } label: {
                    Label(
                        "Exportera retusch…",
                        systemImage: "square.and.arrow.up"
                    )
                }

                Button {
                    controller.importPlate(model: model, pole: pole)
                } label: {
                    Label(
                        "Importera retusch…",
                        systemImage: "square.and.arrow.down"
                    )
                }

                if model.retouchURL(for: pole) != nil {
                    Button("Ta bort retusch", role: .destructive) {
                        model.removeRetouch(for: pole)
                    }
                }
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(model.phase != .ready)

            if model.retouchURL(for: pole) != nil {
                Label(
                    "Retuschen visas ovanpå den vanliga "
                        + "\(pole.displayName.lowercased())reparationen.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            } else {
                Text(
                    "AI-retuschera direkt eller exportera den plana kubsidan "
                        + "och redigera den i ett externt bildprogram."
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct AIRetouchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let pole: PanoramaPole

    @State private var prompt: String
    @State private var source: AIRetouchSource?
    @State private var preview: AIRetouchPreview?
    @State private var maskData: Data?
    @State private var maskHistory: [Data?] = []
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var isWorking = false
    @State private var storedAPIKey: String?
    @State private var isAPIKeySheetPresented = false

    private let keyStore = OpenAIAPIKeyStore()

    init(model: AppModel, pole: PanoramaPole) {
        self.model = model
        self.pole = pole
        _prompt = State(
            initialValue: model.aiRetouchPrompt(for: pole)
                ?? Self.defaultPrompt(for: pole)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI-retuschera \(pole.displayName.lowercased())")
                    .font(.title2.bold())
                Text(
                    "Bilden skickas till OpenAI. Ingen retusch aktiveras "
                        + "förrän du väljer Använd."
                )
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                AIRetouchImagePane(
                    title: "Före",
                    footer: "Dra panorerar · rulla zoomar · ⌘-dra målar · "
                        + "⌘⌥-dra suddar · ⌘Z ångrar"
                ) {
                    if let source {
                        AIRetouchImageViewport(
                            url: source.sourceURL,
                            maskData: maskData,
                            interaction: .mask,
                            isEnabled: !isWorking,
                            onMaskChange: applyMaskChange,
                            onUndo: undoMaskChange
                        )
                        .id("ai-retouch-before-viewport")
                    } else {
                        AIRetouchImagePlaceholder(
                            text: "Förbereder bilden…",
                            showsProgress: errorMessage == nil
                        )
                    }
                } trailing: {
                    Button("Rensa mask", action: clearMask)
                        .disabled(maskData == nil || isWorking)
                }
                .background {
                    AIRetouchMaskUndoMonitor(onUndo: undoMaskChange)
                }

                AIRetouchImagePane(
                    title: "Efter",
                    footer: "Dra panorerar · rulla eller nyp zoomar"
                ) {
                    if let preview {
                        AIRetouchImageViewport(
                            url: preview.editedURL,
                            maskData: nil,
                            interaction: .pan,
                            isEnabled: true,
                            onMaskChange: { _ in },
                            onUndo: {}
                        )
                        .id("ai-retouch-after-viewport")
                    } else {
                        AIRetouchImagePlaceholder(
                            text: "AI-resultatet visas här efter retuschering."
                        )
                    }
                } trailing: {
                    EmptyView()
                }
            }
            .frame(height: 430)

            GroupBox("Instruktion") {
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 82, maxHeight: 110)
                    .padding(6)
            }

            apiKeyRow

            if isWorking {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("OpenAI retuscherar bilden… Det kan ta upp till två minuter.")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Avbryt", role: .cancel) {
                    cancelAndDismiss()
                }
                Spacer()
                if preview != nil {
                    Button("Försök igen") {
                        generate()
                    }
                    .disabled(isWorking || !canGenerate)

                    Button("Använd") {
                        applyPreview()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
                } else {
                    Button("AI-retuschera") {
                        generate()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || !canGenerate)
                }
            }
        }
        .padding(22)
        .frame(
            minWidth: 760,
            idealWidth: 900,
            minHeight: 720,
            idealHeight: 820
        )
        .task {
            storedAPIKey = keyStore.load()
            await loadSource()
        }
        .sheet(isPresented: $isAPIKeySheetPresented) {
            OpenAIAPIKeySheet {
                storedAPIKey = keyStore.load()
            }
        }
        .onDisappear {
            generationTask?.cancel()
            if let preview {
                model.discardAIRetouchPreview(preview)
            }
            if let source {
                model.discardAIRetouchSource(source)
            }
        }
    }

    private var canGenerate: Bool {
        storedAPIKey != nil
            && source != nil
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadSource() async {
        guard source == nil else { return }
        do {
            source = try await model.createAIRetouchSource(for: pole)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generate() {
        errorMessage = nil
        model.setAIRetouchPrompt(prompt, for: pole)
        guard let apiKey = keyStore.load() else {
            storedAPIKey = nil
            errorMessage = OpenAIImageEditError.missingAPIKey.localizedDescription
            return
        }
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
                    for: pole,
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
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyPreview() {
        guard let preview else { return }
        do {
            try model.applyAIRetouchPreview(preview)
            model.discardAIRetouchPreview(preview)
            self.preview = nil
            dismiss()
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
        dismiss()
    }

    private func applyMaskChange(_ newMaskData: Data?) {
        guard !isWorking, newMaskData != maskData else { return }
        maskHistory.append(maskData)
        maskData = newMaskData
        invalidatePreview()
    }

    private func undoMaskChange() {
        guard !isWorking, let previous = maskHistory.popLast() else { return }
        maskData = previous
        invalidatePreview()
    }

    private func clearMask() {
        guard !isWorking, maskData != nil else { return }
        maskHistory.append(maskData)
        maskData = nil
        invalidatePreview()
    }

    private func invalidatePreview() {
        guard let preview else { return }
        model.discardAIRetouchPreview(preview)
        self.preview = nil
    }

    private var apiKeyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal")
                .foregroundStyle(.secondary)
            if let description = OpenAIAPIKeyStore.redactedDescription(
                for: storedAPIKey
            ) {
                Text("OpenAI API-nyckel")
                    .foregroundStyle(.secondary)
                Text(description)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Ändra…") {
                    isAPIKeySheetPresented = true
                }
            } else {
                Text("OpenAI API-nyckel saknas")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Ange…") {
                    isAPIKeySheetPresented = true
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 4)
    }

    private static func defaultPrompt(for pole: PanoramaPole) -> String {
        let surface = pole == .nadir ? "nadirytan" : "zenitytan"
        return "Detta är \(surface) i ett 360°-panorama. Retuschera endast "
            + "det maskerade området. Ta bort kamerastativ, monopod, fotograf, "
            + "skuggor och svarta eller tomma områden inom masken. Rekonstruera "
            + "det skymda underlaget fotorealistiskt utifrån omgivningen. "
            + "Fortsätt befintliga strukturer, linjer, mönster, fogar, plankor, "
            + "stenar och objekt geometriskt och perspektiviskt korrekt genom "
            + "det maskerade området. Bevara originalets ljus, färg, kontrast, "
            + "skärpa, textur och brus. Lägg inte till nya objekt eller detaljer "
            + "som inte kan härledas från omgivningen. Ändra ingenting utanför "
            + "det maskerade området."
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            draw(maskImage, fraction: 0.48, operation: .sourceOver)
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
                : NSColor.systemRed.withAlphaComponent(0.72)).setFill()
            path.fill()
        } else {
            (isErasingStroke
                ? NSColor.white.withAlphaComponent(0.72)
                : NSColor.systemRed.withAlphaComponent(0.72)).setStroke()
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
