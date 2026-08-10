import AppKit
import SwiftUI

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
