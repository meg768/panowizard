import AppKit
import SwiftUI
import UniformTypeIdentifiers

private final class FileMenuDelegateProxy: NSObject, NSMenuDelegate {
    weak var forwardedDelegate: (any NSMenuDelegate)?

    func menuNeedsUpdate(_ menu: NSMenu) {
        forwardedDelegate?.menuNeedsUpdate?(menu)
        hideEmptyPlaceholder(in: menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        forwardedDelegate?.menuWillOpen?(menu)
        hideEmptyPlaceholder(in: menu)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector)
            || forwardedDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if forwardedDelegate?.responds(to: selector) == true {
            return forwardedDelegate
        }
        return super.forwardingTarget(for: selector)
    }

    func hideEmptyPlaceholder(in menu: NSMenu) {
        for item in menu.items where
            item.title == "NSMenuItem"
                && item.action == nil
                && item.submenu == nil {
            item.isHidden = true
        }
    }
}

@MainActor
private final class PanoWizardApplicationDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: PanoWizardApplicationDelegate?

    private weak var pendingTerminationWindow: NSWindow?
    private var discardedTerminationWindows: Set<ObjectIdentifier> = []
    private let fileMenuDelegateProxy = FileMenuDelegateProxy()

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        let dirtyWindow = sender.windows.first { window in
            window.isVisible
                && window.isDocumentEdited
                && !discardedTerminationWindows.contains(ObjectIdentifier(window))
        }
        guard let dirtyWindow else { return .terminateNow }

        pendingTerminationWindow = dirtyWindow
        dirtyWindow.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            dirtyWindow.performClose(nil)
        }
        return .terminateCancel
    }

    func cancelPendingTermination(for window: NSWindow?) {
        guard pendingTerminationWindow === window else { return }
        pendingTerminationWindow = nil
        discardedTerminationWindows.removeAll()
    }

    func discardAndContinueTermination(for window: NSWindow?) {
        guard let window, pendingTerminationWindow === window else { return }
        discardedTerminationWindows.insert(ObjectIdentifier(window))
        continuePendingTermination(for: window)
    }

    func continuePendingTermination(for window: NSWindow?) {
        guard pendingTerminationWindow === window else { return }
        pendingTerminationWindow = nil
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installFileMenuCleanupWhenReady(attempt: 0)
        openWelcomeWindowWhenReady(attempt: 0)
    }

    func applicationDidUpdate(_ notification: Notification) {
        installFileMenuDelegateIfAvailable()
    }

    private func installFileMenuCleanupWhenReady(attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard self.installFileMenuDelegateIfAvailable() else {
                if attempt < 20 {
                    self.installFileMenuCleanupWhenReady(attempt: attempt + 1)
                }
                return
            }
        }
    }

    @discardableResult
    private func installFileMenuDelegateIfAvailable() -> Bool {
        guard let fileMenu = NSApp.mainMenu?.items
            .first(where: { $0.submenu?.items.contains(where: {
                $0.action == #selector(NSDocumentController.openDocument(_:))
            }) == true })?
            .submenu else { return false }

        if fileMenu.delegate !== fileMenuDelegateProxy {
            fileMenuDelegateProxy.forwardedDelegate = fileMenu.delegate
            fileMenu.delegate = fileMenuDelegateProxy
        }
        fileMenuDelegateProxy.hideEmptyPlaceholder(in: fileMenu)
        return true
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
    let showPreview: () -> Void
    let showExport: () -> Void
}

struct ProjectDocumentCommandActions {
    let save: () -> Void
    let saveAs: () -> Void
}

private struct ProjectDocumentCommandActionsKey: FocusedValueKey {
    typealias Value = ProjectDocumentCommandActions
}

private struct PanoramaCommandActionsKey: FocusedValueKey {
    typealias Value = PanoramaCommandActions
}

extension FocusedValues {
    var panoramaCommandActions: PanoramaCommandActions? {
        get { self[PanoramaCommandActionsKey.self] }
        set { self[PanoramaCommandActionsKey.self] = newValue }
    }

    var projectDocumentCommandActions: ProjectDocumentCommandActions? {
        get { self[ProjectDocumentCommandActionsKey.self] }
        set { self[ProjectDocumentCommandActionsKey.self] = newValue }
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
                .background(WindowStateRestorer())
        }
        .defaultSize(width: 1_240, height: 780)
        .commands {
            ProjectDocumentMenuCommands()
            PanoramaMenuCommands()
        }
    }
}

private struct ProjectDocumentMenuCommands: Commands {
    @FocusedValue(\.projectDocumentCommandActions)
    private var actions

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Stäng") {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil)
            }
            .keyboardShortcut("w")

            Divider()

            Button("Spara") {
                actions?.save()
            }
            .keyboardShortcut("s")
            .disabled(actions == nil)

            Button("Spara som…") {
                actions?.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(actions == nil)
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

private struct WindowStateRestorer: NSViewRepresentable {
    @MainActor
    final class Coordinator {
        private static let frameName = "PanoWizard.ProjectWindow"
        private static let zoomedKey = "PanoWizard.ProjectWindow.isZoomed"
        weak var window: NSWindow?
        var observers: [NSObjectProtocol] = []

        @MainActor
        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            window.setFrameAutosaveName(Self.frameName)

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
        func detach() {
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
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(to: window)
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
    @State private var model: AppModel
    @State private var savedDocument: PanoProjectDocument
    @State private var saveURL: URL?
    @State private var projectWindow: NSWindow?
    @State private var saveError: String?

    init(document: Binding<PanoProjectDocument>, documentURL: URL?) {
        let initialDocument = documentURL.flatMap {
            try? PanoProjectDocument(contentsOf: $0)
        } ?? document.wrappedValue
        _savedDocument = State(initialValue: initialDocument)
        _saveURL = State(initialValue: documentURL)
        _model = State(initialValue: AppModel.live(
            project: initialDocument.project,
            masks: initialDocument.masks,
            protectedMasks: initialDocument.protectedMasks,
            panoramaData: initialDocument.panoramaData,
            nadirOverlayData: initialDocument.nadirOverlayData,
            zenithOverlayData: initialDocument.zenithOverlayData,
            nadirRetouchData: initialDocument.nadirRetouchData,
            zenithRetouchData: initialDocument.zenithRetouchData,
            nadirAIRetouchResultData: initialDocument.nadirAIRetouchResultData,
            zenithAIRetouchResultData: initialDocument.zenithAIRetouchResultData
        ))
    }

    var body: some View {
        ContentView(
            model: model,
            projectName: saveURL?
                .deletingPathExtension()
                .lastPathComponent,
            projectDirectoryURL: saveURL?.deletingLastPathComponent()
                ?? model.sourceDirectoryURL
        )
            .navigationSubtitle(isDirty ? "Redigerad" : "")
            .focusedSceneValue(
                \.projectDocumentCommandActions,
                ProjectDocumentCommandActions(
                    save: { _ = save() },
                    saveAs: { _ = saveAs() }
                )
            )
            .background(ProjectWindowAccessor { window in
                projectWindow = window
                updateWindowState()
            })
            .onChange(of: isDirty) {
                updateWindowState()
            }
            .onChange(of: model.maskRevision) {
                updateWindowState()
            }
            .dismissalConfirmationDialog(
                "Vill du spara ändringarna?",
                shouldPresent: isDirty
            ) {
                Button("Spara", role: .cancel) {
                    DispatchQueue.main.async {
                        saveBeforeClosing()
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("Spara inte", role: .destructive) {
                    PanoWizardApplicationDelegate.shared?
                        .discardAndContinueTermination(for: projectWindow)
                }
                Button("Avbryt", role: .cancel) {
                    PanoWizardApplicationDelegate.shared?
                        .cancelPendingTermination(for: projectWindow)
                }
            } message: {
                Text("Ändringarna går förlorade om du inte sparar dem.")
            }
            .alert("Kunde inte spara", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Okänt fel")
            }
            .onAppear {
                dismissWindow(id: "welcome")
                updateWindowState()
            }
    }

    private var workingDocument: PanoProjectDocument {
        let hasNewPanoramaData = model.panoramaRevision > 0
        return PanoProjectDocument(
            project: model.project,
            masks: model.maskDataByImageID,
            protectedMasks: model.protectedMaskDataByImageID,
            panoramaData: hasNewPanoramaData
                ? model.panoramaData
                : savedDocument.panoramaData,
            nadirOverlayData: hasNewPanoramaData
                ? model.nadirOverlayData
                : savedDocument.nadirOverlayData,
            zenithOverlayData: hasNewPanoramaData
                ? model.zenithOverlayData
                : savedDocument.zenithOverlayData,
            nadirRetouchData: hasNewPanoramaData
                ? model.nadirRetouchData
                : savedDocument.nadirRetouchData,
            zenithRetouchData: hasNewPanoramaData
                ? model.zenithRetouchData
                : savedDocument.zenithRetouchData,
            nadirAIRetouchResultData: hasNewPanoramaData
                ? model.nadirAIRetouchResultData
                : savedDocument.nadirAIRetouchResultData,
            zenithAIRetouchResultData: hasNewPanoramaData
                ? model.zenithAIRetouchResultData
                : savedDocument.zenithAIRetouchResultData
        )
    }

    private var isDirty: Bool {
        saveURL == nil || workingDocument != savedDocument
    }

    @discardableResult
    private func save() -> Bool {
        guard let saveURL else { return saveAs() }
        return writeWorkingDocument(to: saveURL)
    }

    @discardableResult
    private func saveAs() -> Bool {
        let panel = makeSavePanel()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return writeWorkingDocument(to: url)
    }

    private func saveBeforeClosing() {
        if let saveURL {
            guard writeWorkingDocument(to: saveURL) else {
                PanoWizardApplicationDelegate.shared?
                    .cancelPendingTermination(for: projectWindow)
                return
            }
            projectWindow?.performClose(nil)
            PanoWizardApplicationDelegate.shared?
                .continuePendingTermination(for: projectWindow)
            return
        }

        let panel = makeSavePanel()
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                PanoWizardApplicationDelegate.shared?
                    .cancelPendingTermination(for: projectWindow)
                return
            }
            DispatchQueue.main.async {
                guard writeWorkingDocument(to: url) else {
                    PanoWizardApplicationDelegate.shared?
                        .cancelPendingTermination(for: projectWindow)
                    return
                }
                projectWindow?.performClose(nil)
                PanoWizardApplicationDelegate.shared?
                    .continuePendingTermination(for: projectWindow)
            }
        }
    }

    private func makeSavePanel() -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.panoWizardProject]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = true
        panel.title = "Spara panorama"
        panel.prompt = "Spara"
        panel.directoryURL = saveURL?.deletingLastPathComponent()
            ?? model.sourceDirectoryURL
        panel.nameFieldStringValue = saveURL?
            .deletingPathExtension()
            .lastPathComponent
            ?? "Namnlöst"
        return panel
    }

    private func writeWorkingDocument(to url: URL) -> Bool {
        let snapshot = workingDocument
        do {
            try snapshot.writeAtomically(to: url)
            saveURL = url
            savedDocument = snapshot
            synchronizeSystemDocument(with: url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            updateWindowState()
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func synchronizeSystemDocument(with url: URL) {
        guard let systemDocument = projectWindow?.windowController?.document
                as? NSDocument else {
            projectWindow?.representedURL = url
            return
        }
        systemDocument.fileURL = url
        systemDocument.fileType = UTType.panoWizardProject.identifier
        systemDocument.fileModificationDate = try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        systemDocument.updateChangeCount(.changeCleared)
    }

    private func updateWindowState() {
        guard let projectWindow else { return }
        let dirty = isDirty
        projectWindow.isDocumentEdited = dirty
    }
}

private struct ProjectWindowAccessor: NSViewRepresentable {
    let resolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        resolveWindow(for: view)
    }

    private func resolveWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            resolve(window)
        }
    }
}
