import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PanoramaLaunchView: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @State private var isImporting = false
    @State private var importError: String?
    @State private var dialogWindow: NSWindow?

    var body: some View {
        PanoramaWelcomeView(
            isImporting: isImporting,
            chooseImages: chooseImages,
            openProject: chooseProject,
            quit: { NSApp.stopModal(); NSApp.terminate(nil) }
        )
        .alert("Could Not Open", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
        .background(StartupDialogWindow { dialogWindow = $0 })
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Choose Source Images"
        panel.prompt = "Choose Images"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        importImages(panel.urls)
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.panoWizardProject]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open Panorama"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        NSApp.stopModal()
        Task {
            do {
                try await openDocument(at: url)
                NSApp.stopModal()
                dialogWindow?.close()
            } catch {
                importError = error.localizedDescription
                resumeDialog()
            }
        }
    }

    private func resumeDialog() {
        guard let dialogWindow else { return }
        DispatchQueue.main.async {
            guard dialogWindow.isVisible, NSApp.modalWindow == nil else { return }
            NSApp.runModal(for: dialogWindow)
        }
    }

    private func importImages(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        NSApp.stopModal()
        Task {
            let accessedURLs = urls.filter {
                $0.startAccessingSecurityScopedResource()
            }
            defer {
                accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            }

            let result = await ImageImportService(
                metadataReader: ImageMetadataReader()
            ).load(from: urls)
            let images = PanoramaGroupingService()
                .group(result.images)
                .flatMap(\.images)
            guard !images.isEmpty else {
                isImporting = false
                importError = "None of the selected files could be read as an image."
                resumeDialog()
                return
            }

            var project = PanoProject()
            project.replaceImages(images)
            let document = PanoProjectDocument(project: project)
            isImporting = false
            NSApp.stopModal()
            newDocument(document)
            dialogWindow?.close()
        }
    }
}

struct PanoramaWelcomeView: View {
    let isImporting: Bool
    let chooseImages: () -> Void
    let openProject: (() -> Void)?
    let quit: () -> Void
    private let backgroundURL = WelcomeBackgroundPicker.currentURL

    var body: some View {
        GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    VStack(spacing: 18) {
                        Image(systemName: "panorama.fill")
                            .font(.system(size: 34, weight: .medium))
                            .symbolRenderingMode(.hierarchical)

                        VStack(spacing: 8) {
                            Text("Create a Panorama")
                                .font(.system(size: 34, weight: .semibold))
                            Text(
                                "Choose overlapping images — PanoWizard handles the rest."
                            )
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.78))
                        }
                        .multilineTextAlignment(.center)

                        Button(action: chooseImages) {
                            HStack(spacing: 9) {
                                if isImporting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                }
                                Text(
                                    isImporting
                                        ? "Reading images…"
                                        : "Create Your Panorama"
                                )
                            }
                            .font(.headline)
                            .foregroundStyle(.black.opacity(0.86))
                            .padding(.horizontal, 22)
                            .frame(width: 300, height: 44)
                            .background(.white.opacity(0.74), in: Capsule())
                            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)

                        if let openProject {
                            Button(action: openProject) {
                                Label("Open Existing Panorama…", systemImage: "folder")
                                    .font(.headline)
                                    .foregroundStyle(.black.opacity(0.86))
                                    .frame(width: 300, height: 44)
                                    .background(.white.opacity(0.74), in: Capsule())
                                    .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                            }
                            .buttonStyle(.plain)
                            .disabled(isImporting)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 3)
                    .padding(.horizontal, 40)

                    Button(action: quit) {
                        Label("Quit", systemImage: "power")
                            .font(.headline)
                            .foregroundStyle(.black.opacity(0.86))
                            .frame(width: 300, height: 44)
                            .background(.white.opacity(0.74), in: Capsule())
                            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                    }
                        .buttonStyle(.plain)
                        .padding(.top, 36)
                        .padding(.bottom, 32)
                        .disabled(isImporting)

                    Spacer(minLength: 24)
                    Spacer(minLength: 24)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(width: StartupDialogLayout.size.width, height: StartupDialogLayout.size.height)
        .background {
            GeometryReader { geometry in
                ZStack {
                    welcomeImage
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    LinearGradient(
                        colors: [.black.opacity(0.18), .black.opacity(0.38), .black.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var welcomeImage: some View {
        if let image = selectedWelcomeImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [Color.blue.opacity(0.75), Color.black.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var selectedWelcomeImage: NSImage? {
        backgroundURL.flatMap(NSImage.init(contentsOf:))
    }
}

private enum WelcomeBackgroundPicker {
    private static let supportedExtensions = Set(["jpg", "jpeg", "png"])
    private static let lastNameKey = "lastWelcomeBackgroundFilename"
    static let currentURL = nextURL()

    private static func nextURL() -> URL? {
        let backgroundsURL = Bundle.main.resourceURL?
            .appendingPathComponent("Backgrounds", isDirectory: true)
        let urls = backgroundsURL.flatMap {
            try? FileManager.default.contentsOfDirectory(
                at: $0,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        }?
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        guard !urls.isEmpty else { return nil }
        let defaults = UserDefaults.standard
        let lastName = defaults.string(forKey: lastNameKey)
        let candidates = urls.filter { $0.lastPathComponent != lastName }
        let url = candidates.randomElement() ?? urls[0]
        defaults.set(url.lastPathComponent, forKey: lastNameKey)
        return url
    }
}


enum StartupDialogLayout {
    static let size: NSSize = {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1_440, height: 900)
        return NSSize(
            width: min(screen.width * 0.9, min(1_100, max(800, screen.width * 0.62))),
            height: min(screen.height * 0.88 - 32, min(740, max(560, screen.height * 0.68)))
        )
    }()
}

private struct StartupDialogWindow: NSViewRepresentable {
    let attach: (NSWindow) -> Void

    private final class AttachmentView: NSView {
        var attach: ((NSWindow) -> Void)?
        private weak var configuredWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window
            window.styleMask.remove([.resizable, .miniaturizable, .closable])
            window.collectionBehavior = [.fullScreenNone]
            window.setContentSize(StartupDialogLayout.size)
            window.center()
            attach?(window)
            DispatchQueue.main.async { [weak window] in
                guard let window, window.isVisible else { return }
                NSApp.runModal(for: window)
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = AttachmentView()
        view.attach = attach
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        if NSApp.modalWindow === nsView.window { NSApp.stopModal() }
    }
}
