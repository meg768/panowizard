import AppKit
import SwiftUI

struct PanoramaCommandActions {
    let canOpenProjectViews: Bool
    let canShowPanorama: Bool
    let canStitch: Bool
    let createPanorama: () -> Void
    let restartAutomatically: () -> Void
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
    var body: some Scene {
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

            Button("Börja om automatiskt…") {
                actions?.restartAutomatically()
            }
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

            Button("Föreslå för aktuellt bildpar") {
                actions?.suggestPairPoints()
            }
            .keyboardShortcut("f", modifiers: .option)
            .disabled(actions?.canSuggest != true)

            Button("Föreslå för hela projektet") {
                actions?.suggestProjectPoints()
            }
            .keyboardShortcut("f", modifiers: [.option, .shift])
            .disabled(actions?.canSuggestProject != true)

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

            if UserDefaults.standard.bool(forKey: Self.zoomedKey) {
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
            zenithOverlayData: document.wrappedValue.zenithOverlayData
        ))
    }

    var body: some View {
        ContentView(
            model: model,
            projectName: documentURL?
                .deletingPathExtension()
                .lastPathComponent,
            projectDirectoryURL: documentURL?.deletingLastPathComponent()
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
            }
    }
}
