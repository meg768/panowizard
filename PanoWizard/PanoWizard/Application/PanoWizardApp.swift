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
    // An off-menu help menu suppresses AppKit's automatic Spotlight Search field.
    private let spotlightHelpMenu = NSMenu()

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

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.helpMenu = spotlightHelpMenu
        installFileMenuCleanupWhenReady(attempt: 0)
        guard notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true
        else { return }
        DispatchQueue.main.async {
            guard ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil,
                  NSDocumentController.shared.documents.isEmpty else { return }
            NSDocumentController.shared.newDocument(nil)
        }
    }

    func applicationDidUpdate(_ notification: Notification) {
        if NSApp.helpMenu !== spotlightHelpMenu {
            NSApp.helpMenu = spotlightHelpMenu
        }
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


}

struct PanoramaCommandActions {
    let canOpenProjectViews: Bool
    let canShowPanorama: Bool
    let canStitch: Bool
    let createPanorama: () -> Void
    let showPreview: () -> Void
    let showRetouch: () -> Void
    let showExport: () -> Void
}

struct ImageCommandItem: Identifiable {
    let id: SourceImage.ID
    let filename: String
    let isSelected: Bool
}

struct ImagesCommandActions {
    let canNavigateImage: Bool
    let images: [ImageCommandItem]
    let addImages: () -> Void
    let removeAllImages: () -> Void
    let selectImage: (SourceImage.ID) -> Void
}

struct ProjectDocumentCommandActions {
    let canRevert: Bool
    let save: () -> Void
    let saveAs: () -> Void
    let revert: () -> Void
}

struct SourceMaskCommandActions {
    let canUndo: Bool
    let undo: () -> Void
}

private struct ProjectDocumentCommandActionsKey: FocusedValueKey {
    typealias Value = ProjectDocumentCommandActions
}

private struct PanoramaCommandActionsKey: FocusedValueKey {
    typealias Value = PanoramaCommandActions
}

private struct ImagesCommandActionsKey: FocusedValueKey {
    typealias Value = ImagesCommandActions
}

private struct SourceMaskCommandActionsKey: FocusedValueKey {
    typealias Value = SourceMaskCommandActions
}

extension FocusedValues {
    var imagesCommandActions: ImagesCommandActions? {
        get { self[ImagesCommandActionsKey.self] }
        set { self[ImagesCommandActionsKey.self] = newValue }
    }

    var panoramaCommandActions: PanoramaCommandActions? {
        get { self[PanoramaCommandActionsKey.self] }
        set { self[PanoramaCommandActionsKey.self] = newValue }
    }

    var projectDocumentCommandActions: ProjectDocumentCommandActions? {
        get { self[ProjectDocumentCommandActionsKey.self] }
        set { self[ProjectDocumentCommandActionsKey.self] = newValue }
    }

    var sourceMaskCommandActions: SourceMaskCommandActions? {
        get { self[SourceMaskCommandActionsKey.self] }
        set { self[SourceMaskCommandActionsKey.self] = newValue }
    }
}

@main
struct PanoWizardApp: App {
    @NSApplicationDelegateAdaptor(PanoWizardApplicationDelegate.self)
    private var applicationDelegate

    var body: some Scene {
        DocumentGroup(newDocument: PanoProjectDocument()) { file in
            ProjectDocumentView(
                document: file.$document,
                documentURL: file.fileURL
            )
                .frame(minWidth: 900, minHeight: 600)
                .background(ProjectWindowSize())
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About PanoWizard") {
                    let info = Bundle.main.infoDictionary ?? [:]
                    let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
                    let timestamp = info["PanoWizardBuildTimestamp"] as? String ?? ""
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: "Version \(version)\nBuild \(timestamp)",
                        .version: "",
                    ])
                }
            }
            ProjectDocumentMenuCommands()
            CommandGroup(replacing: .help) {
                Button("PanoWizard Help") {
                    guard let configuredURL = Bundle.main.object(
                        forInfoDictionaryKey: "PanoWizardHelpURL"
                    ) as? String, let url = URL(string: configuredURL) else { return }
                    NSWorkspace.shared.open(url)
                }
            }
            SourceMaskMenuCommands()
            ImagesMenuCommands()
            PanoramaMenuCommands()
            ImageNavigationMenuCommands()
        }
    }
}

private struct ImageNavigationMenuCommands: Commands {
    @FocusedValue(\.imagesCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Zoom In") {
                ImageNavigationCommands.send(
                    #selector(ImageNavigationResponder.zoomImageIn(_:))
                )
            }
            .keyboardShortcut("+")
            .disabled(actions?.canNavigateImage != true)

            Button("Zoom Out") {
                ImageNavigationCommands.send(
                    #selector(ImageNavigationResponder.zoomImageOut(_:))
                )
            }
            .keyboardShortcut("-")
            .disabled(actions?.canNavigateImage != true)

            Button("Reset View") {
                ImageNavigationCommands.send(
                    #selector(ImageNavigationResponder.resetImageView(_:))
                )
            }
            .keyboardShortcut("0")
            .disabled(actions?.canNavigateImage != true)
        }
    }
}

private struct SourceMaskMenuCommands: Commands {
    @FocusedValue(\.sourceMaskCommandActions)
    private var actions

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Mask Change") {
                actions?.undo()
            }
            .keyboardShortcut("z")
            .disabled(actions?.canUndo != true)
        }
    }
}

private struct ImagesMenuCommands: Commands {
    @FocusedValue(\.imagesCommandActions)
    private var actions

    var body: some Commands {
        CommandMenu("Images") {
            Button("Add...") { actions?.addImages() }
                .disabled(actions == nil)
            Button("Remove All…") { actions?.removeAllImages() }
                .disabled(actions?.images.isEmpty != false)
            if !(actions?.images.isEmpty ?? true) { Divider() }
            ForEach(
                Array((actions?.images ?? []).enumerated()),
                id: \.element.id
            ) { index, image in
                if index < 9 {
                    imageButton(image, number: index + 1)
                        .keyboardShortcut(
                            KeyEquivalent(Character(String(index + 1))),
                            modifiers: .option
                        )
                } else {
                    imageButton(image, number: index + 1)
                }
            }
        }
    }

    private func imageButton(
        _ image: ImageCommandItem,
        number: Int
    ) -> some View {
        Button {
            actions?.selectImage(image.id)
        } label: {
            let title = image.filename
            if image.isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

private struct ProjectDocumentMenuCommands: Commands {
    @FocusedValue(\.projectDocumentCommandActions)
    private var actions

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Close") {
                (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil)
            }
            .keyboardShortcut("w")

            Divider()

            Button("Save") {
                actions?.save()
            }
            .keyboardShortcut("s")
            .disabled(actions == nil)

            Button("Save As…") {
                actions?.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Divider()

            Button("Revert") {
                actions?.revert()
            }
            .disabled(actions?.canRevert != true)
        }
    }
}

private struct PanoramaMenuCommands: Commands {
    @FocusedValue(\.panoramaCommandActions)
    private var actions

    var body: some Commands {
        CommandMenu("Panorama") {
            Button("Create") {
                actions?.createPanorama()
            }
            .keyboardShortcut("c", modifiers: .option)
            .disabled(actions?.canStitch != true)

            Divider()

            Button("Retouch") {
                actions?.showRetouch()
            }
            .keyboardShortcut("r", modifiers: .option)
            .disabled(actions?.canShowPanorama != true)

            Button("Preview") {
                actions?.showPreview()
            }
            .keyboardShortcut("p", modifiers: .option)
            .disabled(actions?.canShowPanorama != true)

            Button("Export") {
                actions?.showExport()
            }
            .keyboardShortcut("e", modifiers: .option)
            .disabled(actions?.canShowPanorama != true)
        }
    }
}

private struct ProjectDocumentView: View {
    @State private var model: AppModel?
    @State private var savedDocument: PanoProjectDocument
    @State private var saveURL: URL?
    @State private var projectWindow: NSWindow?
    @State private var saveError: String?
    @State private var saveErrorTitle = "Could Not Save"
    @State private var isRevertConfirmationPresented = false
    @State private var needsSourceResolution: Bool
    @State private var sourceAccessBookmarks: [String: Data]
    @State private var sourceReloadRevision = 0

    init(document: Binding<PanoProjectDocument>, documentURL: URL?) {
        var initialDocument = document.wrappedValue
        if let documentURL {
            initialDocument.sourceAccessBookmarks = SourceFileAccess.shared.restore(
                initialDocument.sourceAccessBookmarks
            )
            // Restore selected-file grants before any preview starts. Relative URLs
            // must not be passed to image loaders or a Save As operation.
            let directory = documentURL.deletingLastPathComponent()
            for index in initialDocument.project.images.indices {
                let url = initialDocument.project.images[index].url
                if !url.isFileURL {
                    initialDocument.project.images[index].url = directory
                        .appending(path: url.path).standardizedFileURL
                }
            }
        }
        _sourceAccessBookmarks = State(initialValue: initialDocument.sourceAccessBookmarks)
        _needsSourceResolution = State(initialValue: documentURL != nil)
        _savedDocument = State(initialValue: initialDocument)
        _saveURL = State(initialValue: documentURL)
        // Source access must be ready before model initialization rebuilds retouch data.
        _model = State(initialValue: nil)
    }

    var body: some View {
        Group {
            if let model {
                ContentView(
                    model: model,
                    projectName: saveURL?
                        .deletingPathExtension()
                        .lastPathComponent,
                    projectDirectoryURL: saveURL?.deletingLastPathComponent()
                        ?? model.sourceDirectoryURL
                )
            } else {
                Color.clear
            }
        }
            .id(sourceReloadRevision)
            .focusedSceneValue(
                \.projectDocumentCommandActions,
                ProjectDocumentCommandActions(
                    canRevert: saveURL != nil && isDirty,
                    save: { _ = save() },
                    saveAs: { _ = saveAs() },
                    revert: { isRevertConfirmationPresented = true }
                )
            )
            .background(ProjectWindowAccessor { window in
                projectWindow = window
                updateWindowState()
            })
            .onChange(of: isDirty) {
                updateWindowState()
            }
            .onChange(of: model?.maskRevision) {
                updateWindowState()
            }
            .onChange(of: model?.aiRetouchMaskRevision) {
                updateWindowState()
            }
            .dismissalConfirmationDialog(
                "Do You Want to Save Your Changes?",
                shouldPresent: isDirty
            ) {
                Button("Save", role: .cancel) {
                    DispatchQueue.main.async {
                        saveBeforeClosing()
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("Don't Save", role: .destructive) {
                    PanoWizardApplicationDelegate.shared?
                        .discardAndContinueTermination(for: projectWindow)
                }
                Button("Cancel", role: .cancel) {
                    PanoWizardApplicationDelegate.shared?
                        .cancelPendingTermination(for: projectWindow)
                }
            } message: {
                Text("Your changes will be lost if you don't save them.")
            }
            .confirmationDialog(
                "Revert to the Last Saved Version?",
                isPresented: $isRevertConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Revert", role: .destructive) {
                    revertToSavedDocument()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All changes since the last save will be lost.")
            }
            .alert(saveErrorTitle, isPresented: Binding(
                get: { saveError != nil },
                set: {
                    if !$0 {
                        saveError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Unknown error")
            }
            .onAppear {
                updateWindowState()
            }
            .task {
                await Task.yield()
                if saveURL != nil {
                    resolveSourcesIfNeeded()
                } else if model == nil {
                    model = AppModel.live(
                        project: savedDocument.project,
                        masks: savedDocument.masks,
                        protectedMasks: savedDocument.protectedMasks,
                        panoramaData: savedDocument.panoramaData,
                        retouchPatchData: savedDocument.retouchPatchData,
                        aiRetouchMaskData: savedDocument.aiRetouchMaskData
                    )
                }
            }
    }

    private func resolveSourcesIfNeeded(force: Bool = false) {
        guard needsSourceResolution || force, let saveURL else { return }
        defer { needsSourceResolution = false }
        do {
            let document = try PanoProjectDocument(contentsOf: saveURL)
            savedDocument = document
            sourceAccessBookmarks.merge(document.sourceAccessBookmarks) { _, updated in updated }
            model = AppModel.live(
                project: document.project,
                masks: document.masks,
                protectedMasks: document.protectedMasks,
                panoramaData: document.panoramaData,
                retouchPatchData: document.retouchPatchData,
                aiRetouchMaskData: document.aiRetouchMaskData
            )
            saveError = nil
            if force { sourceReloadRevision += 1 }
            updateWindowState()
        } catch {
            presentSourceReadError(error)
        }
    }

    private func presentSourceReadError(_ error: Error) {
        if let permission = error as? SourceFileAccess.PermissionRequired {
            DispatchQueue.main.async {
                grantSourceAccess(for: permission.sourceURLs)
            }
            return
        }
        saveErrorTitle = "Could Not Read Source Images"
        saveError = error.localizedDescription
    }

    private func grantSourceAccess(for sourceURLs: [URL]) {
        // The native picker confirms each required folder grant. Recheck after
        // each grant: one folder may cover many sources or several subfolders.
        let remaining = sourceURLs.filter { !SourceFileAccess.canOpenSource(at: $0) }
        guard let first = remaining.first else {
            resolveSourcesIfNeeded(force: true)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = first.deletingLastPathComponent()
        panel.title = "Grant Access to Source Images"
        panel.prompt = "Grant Access"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let folderURL = panel.url else { return }
            do {
                try SourceFileAccess.shared.retain(folderURL)
                sourceAccessBookmarks = SourceFileAccess.shared.bookmarks(
                    for: (model?.project ?? savedDocument.project).images.map(\.url), preserving: sourceAccessBookmarks
                )
                DispatchQueue.main.async {
                    grantSourceAccess(for: remaining)
                }
            } catch {
                presentSourceReadError(error)
            }
        }
        if let projectWindow {
            panel.beginSheetModal(for: projectWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private var workingDocument: PanoProjectDocument {
        guard let model else {
            var document = savedDocument
            document.sourceAccessBookmarks = sourceAccessBookmarks
            return document
        }
        let hasNewPanoramaData = model.panoramaRevision > 0
        return PanoProjectDocument(
            project: model.project,
            masks: model.maskDataByImageID,
            protectedMasks: model.protectedMaskDataByImageID,
            panoramaData: hasNewPanoramaData
                ? model.panoramaData
                : savedDocument.panoramaData,
            retouchPatchData: hasNewPanoramaData
                ? model.retouchPatchData
                : savedDocument.retouchPatchData,
            aiRetouchMaskData: model.aiRetouchMaskDataByPatchID,
            sourceAccessBookmarks: sourceAccessBookmarks
        )
    }

    private var isDirty: Bool {
        workingDocument != savedDocument
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
        panel.title = "Save Panorama"
        panel.prompt = "Save"
        panel.directoryURL = saveURL?.deletingLastPathComponent()
            ?? model?.sourceDirectoryURL
        panel.nameFieldStringValue = saveURL?
            .deletingPathExtension()
            .lastPathComponent
            ?? (savedDocument.project.title == "Untitled Panorama" ? "Untitled" : savedDocument.project.title)
        return panel
    }

    private func writeWorkingDocument(to url: URL) -> Bool {
        var snapshot = workingDocument
        snapshot.sourceAccessBookmarks = SourceFileAccess.shared.bookmarks(
            for: snapshot.project.images.map(\.url), preserving: snapshot.sourceAccessBookmarks
        )
        do {
            try snapshot.writeAtomically(to: url)
            sourceAccessBookmarks = snapshot.sourceAccessBookmarks
            saveURL = url
            savedDocument = snapshot
            synchronizeSystemDocument(with: url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            updateWindowState()
            return true
        } catch {
            saveErrorTitle = "Could Not Save"
            saveError = error.localizedDescription
            return false
        }
    }

    private func revertToSavedDocument() {
        guard let saveURL else { return }
        do {
            let document = try PanoProjectDocument(contentsOf: saveURL)
            savedDocument = document
            sourceAccessBookmarks.merge(document.sourceAccessBookmarks) { _, updated in updated }
            model = AppModel.live(
                project: document.project,
                masks: document.masks,
                protectedMasks: document.protectedMasks,
                panoramaData: document.panoramaData,
                retouchPatchData: document.retouchPatchData,
                aiRetouchMaskData: document.aiRetouchMaskData
            )
            synchronizeSystemDocument(with: saveURL)
            updateWindowState()
        } catch {
            if error is SourceFileAccess.PermissionRequired {
                presentSourceReadError(error)
            } else {
                saveErrorTitle = "Could Not Revert"
                saveError = error.localizedDescription
            }
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
        if saveURL == nil, savedDocument.project.title != "Untitled Panorama" {
            projectWindow.title = savedDocument.project.title
        }
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

/// Shares only normal project content size. Position and screen state stay with macOS.
private struct ProjectWindowSize: NSViewRepresentable {
    private final class AttachmentView: NSView {
        private weak var attachedWindow: NSWindow?
        private var observer: NSObjectProtocol?
        private static let widthKey = "PanoWizard.ProjectWindow.contentWidth"
        private static let heightKey = "PanoWizard.ProjectWindow.contentHeight"

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard attachedWindow !== window else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            attachedWindow = window
            guard let window else { return }
            let defaults = UserDefaults.standard
            let width = defaults.double(forKey: Self.widthKey)
            let height = defaults.double(forKey: Self.heightKey)
            if width > 0, height > 0, !window.styleMask.contains(.fullScreen) {
                let available = window.screen?.visibleFrame.size ?? NSSize(width: width, height: height)
                window.setContentSize(NSSize(
                    width: min(max(width, 900), available.width),
                    height: min(max(height, 600), available.height - 40)
                ))
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveNormalSize() }
            }
        }

        private func saveNormalSize() {
            guard let window = attachedWindow,
                  !window.isZoomed, !window.styleMask.contains(.fullScreen) else { return }
            let size = window.contentRect(forFrameRect: window.frame).size
            if let screen = window.screen?.visibleFrame,
               window.frame.width >= screen.width - 2,
               window.frame.height >= screen.height - 2 { return }
            UserDefaults.standard.set(size.width, forKey: Self.widthKey)
            UserDefaults.standard.set(size.height, forKey: Self.heightKey)
        }

        func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }

    func makeNSView(context: Context) -> NSView { AttachmentView() }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? AttachmentView)?.stopObserving()
    }
}
