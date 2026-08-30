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

            apiKeyRow

            HStack(alignment: .top, spacing: 16) {
                AIRetouchImagePane(
                    title: "Före",
                    footer: "Dra panorerar · rulla eller nyp zoomar"
                ) {
                    if let source {
                        AIRetouchImageViewport(
                            url: source.sourceURL
                        )
                        .id("ai-retouch-before-viewport")
                    } else {
                        AIRetouchImagePlaceholder(
                            text: "Förbereder bilden…",
                            showsProgress: errorMessage == nil
                        )
                    }
                }

                AIRetouchImagePane(
                    title: "Efter",
                    footer: "Dra panorerar · rulla eller nyp zoomar"
                ) {
                    if let preview {
                        AIRetouchImageViewport(
                            url: preview.editedURL
                        )
                        .id("ai-retouch-after-viewport")
                    } else {
                        AIRetouchImagePlaceholder(
                            text: "AI-resultatet visas här efter retuschering."
                        )
                    }
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
        .sheet(isPresented: $isWorking) {
            AIRetouchProgressSheet(onCancel: cancelGeneration)
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

    private func cancelGeneration() {
        generationTask?.cancel()
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
        if pole == .nadir {
            return "Detta är nadirytan i ett 360°-panorama. Ta endast bort "
                + "kameran, kamerastativet, monopoden, fotografen och skuggor "
                + "som tydligt hör till denna kamerautrustning. Rekonstruera "
                + "endast den yta som dessa objekt skymmer. Bevara alla andra "
                + "objekt och delar av bilden exakt som de är, även om de "
                + "befinner sig nära kamerautrustningen. Ta inte bort, flytta, "
                + "förändra eller rekonstruera möbler, soptunnor, rör, avlopp, "
                + "radiatorer, väggar, dörrar, lister eller andra befintliga "
                + "objekt. Bevara originalets geometri, perspektiv, ljus, färg, "
                + "kontrast, skärpa, textur och brus utanför området som faktiskt "
                + "skyms av kamerautrustningen. Rekonstruera det skymda "
                + "underlaget fotorealistiskt utifrån omgivningen och fortsätt "
                + "befintliga strukturer, linjer, mönster, fogar, plankor och "
                + "stenar geometriskt och perspektiviskt korrekt. Resultatet ska "
                + "se ut som originalfotografiet taget från samma position, men "
                + "utan kamerautrustningen. Gör inga andra förändringar."
        }

        return "Detta är zenitytan i ett 360°-panorama. Ta endast bort "
            + "kamerautrustning, fotografen och skuggor eller andra artefakter "
            + "som tydligt hör till fotograferingen. Rekonstruera endast den "
            + "yta som dessa objekt eller artefakter skymmer. Bevara alla andra "
            + "objekt och delar av bilden exakt som de är, även om de befinner "
            + "sig nära området som retuscheras. Ta inte bort, flytta, förändra "
            + "eller rekonstruera lampor, armaturer, ventilationsdon, sprinklers, "
            + "kablar, bjälkar, lister, takdetaljer, väggar, dörrar eller andra "
            + "befintliga objekt. Bevara originalets geometri, perspektiv, ljus, "
            + "färg, kontrast, skärpa, textur och brus utanför området som "
            + "faktiskt behöver rekonstrueras. Rekonstruera det skymda taket "
            + "eller den bakomliggande ytan fotorealistiskt utifrån omgivningen "
            + "och fortsätt befintliga strukturer, linjer, mönster, paneler, "
            + "bjälkar och andra arkitektoniska detaljer geometriskt och "
            + "perspektiviskt korrekt. Resultatet ska se ut som "
            + "originalfotografiet taget från samma position, men utan "
            + "kamerautrustningen eller fotograferingsartefakterna. Gör inga "
            + "andra förändringar."
    }
}

private struct AIRetouchProgressSheet: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.small)

            VStack(spacing: 4) {
                Text("OpenAI retuscherar bilden…")
                    .font(.headline)
                Text("Det kan ta upp till två minuter.")
                    .foregroundStyle(.secondary)
            }

            Button("Avbryt", role: .cancel, action: onCancel)
        }
        .padding(24)
        .frame(width: 320)
        .interactiveDismissDisabled()
    }
}

private struct AIRetouchImagePane<Content: View>: View {
    let title: String
    let footer: String
    let content: Content

    init(
        title: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer()
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

private struct AIRetouchImageViewport: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AIRetouchScrollView {
        AIRetouchScrollView()
    }

    func updateNSView(_ scrollView: AIRetouchScrollView, context: Context) {
        scrollView.configure(url: url)
    }
}

private final class AIRetouchScrollView: NSScrollView {
    private let imageView = AIRetouchImageDocumentView()
    private var imageURL: URL?
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

    func configure(url: URL) {
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
    weak var viewport: AIRetouchScrollView?
    var image: CGImage?

    private var panOrigin: CGPoint?
    private var panStart: CGPoint?

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        draw(image, fraction: 1, operation: .copy)
    }

    override func mouseDown(with event: NSEvent) {
        guard let viewport else { return }
        viewport.beginUserNavigation()
        panOrigin = viewport.contentView.bounds.origin
        panStart = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        pan(to: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        if panOrigin != nil { NSCursor.pop() }
        panOrigin = nil
        panStart = nil
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
}
