import AppKit
import SwiftUI

@MainActor
private final class PanoWizardApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        openWelcomeWindowWhenReady(attempt: 0)
    }

    private func openWelcomeWindowWhenReady(attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard NSApp.windows.allSatisfy({ !$0.isVisible }) else { return }
            if let item = NSApp.windowsMenu?.items.first(where: {
                $0.title == "PanoWizard" && $0.action != nil
            }), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            } else if attempt < 20 {
                self.openWelcomeWindowWhenReady(attempt: attempt + 1)
            }
        }
    }
}

struct PanoramaCommandActions {
    let canOpenProjectViews: Bool
    let canShowPanorama: Bool
    let canStitch: Bool
    let createPanorama: () -> Void
    let showSettings: () -> Void
    let showPreview: () -> Void
    let showExport: () -> Void
}

private struct PanoramaCommandActionsKey: FocusedValueKey {
    typealias Value = PanoramaCommandActions
}

extension FocusedValues {
    var panoramaCommandActions: PanoramaCommandActions? {
        get { self[PanoramaCommandActionsKey.self] }
        set { self[PanoramaCommandActionsKey.self] = newValue }
    }
}

@main
struct PanoWizardApp: App {
    @NSApplicationDelegateAdaptor(PanoWizardApplicationDelegate.self)
    private var applicationDelegate

    var body: some Scene {
        Window("PanoWizard", id: "welcome") {
            PanoramaLaunchView()
        }
        .defaultSize(width: 1_080, height: 680)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        DocumentGroup(newDocument: PanoProjectDocument()) { file in
            ProjectDocumentView(
                document: file.$document,
                documentURL: file.fileURL
            )
                .frame(minWidth: 900, minHeight: 600)
                .background(WindowStateRestorer(
                    documentName: file.fileURL?
                        .deletingPathExtension()
                        .lastPathComponent
                        ?? file.document.project.title
                ))
        }
        .defaultSize(width: 1_240, height: 780)
        .commands {
            PanoramaMenuCommands()
            ControlPointMenuCommands()
        }
    }
}

private struct PanoramaMenuCommands: Commands {
    @FocusedValue(\.panoramaCommandActions)
    private var actions

    var body: some Commands {
        CommandMenu("Panorama") {
            Button("Skapa panorama") {
                actions?.createPanorama()
            }
            .keyboardShortcut("r", modifiers: .option)
            .disabled(actions?.canStitch != true)

            Divider()

            Button("Inställningar") {
                actions?.showSettings()
            }
            .keyboardShortcut(",", modifiers: .option)
            .disabled(actions?.canOpenProjectViews != true)

            Button("Förhandsvisning") {
                actions?.showPreview()
            }
            .keyboardShortcut("p", modifiers: .option)
            .disabled(actions?.canShowPanorama != true)

            Button("Exportera…") {
                actions?.showExport()
            }
            .keyboardShortcut("e", modifiers: .option)
            .disabled(actions?.canShowPanorama != true)
        }
    }
}

private struct ControlPointMenuCommands: Commands {
    @FocusedValue(\.controlPointCommandActions)
    private var actions

    var body: some Commands {
        CommandMenu("Kontrollpunkter") {
            Button(actions?.addPointTitle ?? "Lägg till punkt") {
                actions?.toggleAddingPoint()
            }
            .keyboardShortcut("a", modifiers: .option)
            .disabled(actions == nil)

            Divider()

            Button("Föreslå punkter") {
                actions?.suggestPairPoints()
            }
            .keyboardShortcut("f", modifiers: .option)
            .disabled(actions?.canSuggest != true)

            Button("Generera om alla kontrollpunkter…") {
                actions?.requestRegenerateProjectPoints()
            }
            .disabled(actions?.canRegenerateProject != true)

            Divider()

            Button(actions?.optimizeTitle ?? "Optimera") {
                actions?.optimize()
            }
            .keyboardShortcut("o", modifiers: .option)
            .disabled(actions?.canOptimize != true)

            Divider()

            Button("Radera markerad punkt") {
                actions?.removeSelectedPoint()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(actions?.canRemoveSelectedPoint != true)

            Button("Radera alla i aktuellt bildpar…") {
                actions?.requestRemovePairPoints()
            }
            .disabled(actions?.canRemovePairPoints != true)

            Button("Radera alla kontrollpunkter i projektet…") {
                actions?.requestRemoveProjectPoints()
            }
            .disabled(actions?.canRemoveProjectPoints != true)
        }
    }
}

private struct WindowStateRestorer: NSViewRepresentable {
    let documentName: String

    @MainActor
    final class Coordinator {
        private static let frameName = "PanoWizard.ProjectWindow"
        private static let zoomedKey = "PanoWizard.ProjectWindow.isZoomed"
        weak var window: NSWindow?
        var observers: [NSObjectProtocol] = []
        var documentEditedObservation: NSKeyValueObservation?
        var windowTitleObservation: NSKeyValueObservation?
        var windowSubtitleObservation: NSKeyValueObservation?
        var documentName = ""

        @MainActor
        func attach(to window: NSWindow, documentName: String) {
            self.documentName = documentName
            guard self.window !== window else {
                applyDocumentTitle()
                return
            }
            detach()
            self.window = window
            self.documentName = documentName
            window.setFrameAutosaveName(Self.frameName)

            documentEditedObservation = window.observe(
                \.isDocumentEdited,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor in
                    // SwiftUI first updates the ordinary document subtitle.
                    // Apply our compact one-line form immediately afterwards.
                    await Task.yield()
                    self?.applyDocumentTitle()
                }
            }
            windowTitleObservation = window.observe(
                \.title,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.applyDocumentTitle()
                }
            }
            windowSubtitleObservation = window.observe(
                \.subtitle,
                options: [.new]
            ) { [weak self] _, _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.applyDocumentTitle()
                }
            }

            let center = NotificationCenter.default
            for name in [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.willCloseNotification
            ] {
                observers.append(center.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak window] _ in
                    guard let window else { return }
                    Task { @MainActor in
                        UserDefaults.standard.set(
                            window.isZoomed,
                            forKey: Self.zoomedKey
                        )
                    }
                })
            }

            let savedZoomState = UserDefaults.standard.object(
                forKey: Self.zoomedKey
            ) as? Bool
            if savedZoomState ?? true {
                DispatchQueue.main.async {
                    guard !window.isZoomed else { return }
                    window.zoom(nil)
                }
            }
        }

        @MainActor
        private func applyDocumentTitle() {
            guard let window else { return }
            let title = window.isDocumentEdited
                ? "\(documentName) (redigerad)"
                : documentName
            if window.title != title {
                window.title = title
            }
            if !window.subtitle.isEmpty {
                window.subtitle = ""
            }
        }

        @MainActor
        func detach() {
            documentEditedObservation = nil
            windowTitleObservation = nil
            windowSubtitleObservation = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            window = nil
        }

    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(
                to: window,
                documentName: documentName
            )
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(
                to: window,
                documentName: documentName
            )
        }
    }

    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }
}

private struct ProjectDocumentView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Binding var document: PanoProjectDocument
    @State private var model: AppModel
    let documentURL: URL?

    init(document: Binding<PanoProjectDocument>, documentURL: URL?) {
        _document = document
        self.documentURL = documentURL
        _model = State(initialValue: AppModel.live(
            project: document.wrappedValue.project,
            masks: document.wrappedValue.masks,
            controlPointMasks: document.wrappedValue.controlPointMasks,
            protectedMasks: document.wrappedValue.protectedMasks,
            panoramaData: document.wrappedValue.panoramaData,
            nadirOverlayData: document.wrappedValue.nadirOverlayData,
            zenithOverlayData: document.wrappedValue.zenithOverlayData,
            nadirRetouchData: document.wrappedValue.nadirRetouchData,
            zenithRetouchData: document.wrappedValue.zenithRetouchData
        ))
    }

    var body: some View {
        ContentView(
            model: model,
            projectName: documentURL?
                .deletingPathExtension()
                .lastPathComponent,
            projectDirectoryURL: documentURL?.deletingLastPathComponent()
                ?? model.sourceDirectoryURL
        )
            .onChange(of: model.project) { _, project in
                document.project = project
            }
            .onChange(of: model.maskRevision) {
                document.masks = model.maskDataByImageID
                document.controlPointMasks = model.controlPointMaskDataByImageID
                document.protectedMasks = model.protectedMaskDataByImageID
            }
            .onChange(of: model.panoramaRevision) {
                document.panoramaData = model.panoramaData
                document.nadirOverlayData = model.nadirOverlayData
                document.zenithOverlayData = model.zenithOverlayData
                document.nadirRetouchData = model.nadirRetouchData
                document.zenithRetouchData = model.zenithRetouchData
            }
            .onAppear {
                dismissWindow(id: "welcome")
            }
    }
}
