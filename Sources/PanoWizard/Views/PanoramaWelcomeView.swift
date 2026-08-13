import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PanoramaLaunchView: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var importError: String?

    var body: some View {
        PanoramaWelcomeView(
            isImporting: isImporting,
            isDropTargeted: isDropTargeted,
            chooseImages: chooseImages
        )
        .dropDestination(for: URL.self) { urls, _ in
            importImages(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .alert("Bilderna kunde inte läsas", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Okänt fel")
        }
        .background(WelcomeWindowZoomer())
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Välj källbilder"
        panel.prompt = "Välj bilder"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        importImages(panel.urls)
    }

    private func importImages(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
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
                importError = "Ingen av de valda filerna kunde läsas som en bild."
                return
            }

            var project = PanoProject()
            project.replaceImages(images)
            let document = PanoProjectDocument(project: project)
            isImporting = false
            newDocument(document)
            dismissWindow(id: "welcome")
        }
    }
}

private struct WelcomeWindowZoomer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        zoomWindow(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        zoomWindow(for: view)
    }

    private func zoomWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window, !window.isZoomed else { return }
            window.zoom(nil)
        }
    }
}

struct PanoramaWelcomeView: View {
    let isImporting: Bool
    let isDropTargeted: Bool
    let chooseImages: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                welcomeImage
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(
                    colors: [
                        .black.opacity(0.18),
                        .black.opacity(0.38),
                        .black.opacity(0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    Spacer(minLength: 80)

                    VStack(spacing: 18) {
                        Image(systemName: "panorama.fill")
                            .font(.system(size: 34, weight: .medium))
                            .symbolRenderingMode(.hierarchical)

                        VStack(spacing: 8) {
                            Text("Skapa ett panorama")
                                .font(.system(size: 34, weight: .semibold))
                            Text(
                                "Välj överlappande bilder – PanoWizard ordnar resten."
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
                                        ? "Läser bilder…"
                                        : "Skapa ditt panorama"
                                )
                            }
                            .font(.headline)
                            .foregroundStyle(.black.opacity(0.86))
                            .padding(.horizontal, 22)
                            .frame(height: 44)
                            .background(.white, in: Capsule())
                            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)

                        Text("Du kan också dra in bilder här.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 3)
                    .padding(.horizontal, 40)

                    Spacer(minLength: 80)
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.white.opacity(0.08))
                        .stroke(
                            .white.opacity(0.92),
                            style: StrokeStyle(lineWidth: 3, dash: [10, 7])
                        )
                        .padding(24)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var welcomeImage: some View {
        if let url = Bundle.module.url(
            forResource: "WelcomePanorama",
            withExtension: "jpg"
        ), let image = NSImage(contentsOf: url) {
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
}
