import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct PanoramaExportView: View {
    @Bindable var model: AppModel
    let projectName: String?
    let viewpoint: PanoramaViewpoint

    @State private var jpegQuality = 0.92
    @State private var maximumWidth = 0
    @State private var errorMessage: String?
    @State private var isPreparingHTMLShare = false

    var body: some View {
        if let panoramaURL = model.stitchedResultURL {
            Form {
                Section("Panoramabild") {
                    LabeledContent("Format", value: "Equirektangulär JPEG · 2:1")
                    Picker("Storlek", selection: $maximumWidth) {
                        Text("Original").tag(0)
                        Text("4096 px").tag(4_096)
                        Text("2048 px").tag(2_048)
                    }
                    Picker("Kvalitet", selection: $jpegQuality) {
                        Text("Normal").tag(0.82)
                        Text("Hög").tag(0.92)
                        Text("Maximal").tag(0.98)
                    }
                    HStack {
                        Button {
                            exportJPEG(from: panoramaURL)
                        } label: {
                            Label("Spara JPEG…", systemImage: "photo")
                        }
                        ShareLink(item: panoramaURL) {
                            Label("Dela…", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("Interaktivt panorama") {
                    Text(
                        "En självständig HTML-fil som kan öppnas i en modern "
                            + "webbläsare utan andra tillhörande filer."
                    )
                    .foregroundStyle(.secondary)
                    HStack {
                        Button {
                            exportHTML()
                        } label: {
                            Label("Spara HTML…", systemImage: "safari")
                        }
                        Button {
                            shareHTML()
                        } label: {
                            Label(
                                isPreparingHTMLShare
                                    ? "Förbereder…"
                                    : "Dela HTML (.zip)…",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .disabled(isPreparingHTMLShare)
                    }
                    .disabled(!model.canExportHTML)
                }

                if model.project.nadirRepairPlacement != nil,
                   !model.isNadirPreviewBlended {
                    Section {
                        Label(
                            "Nadirreparationen måste blandas färdigt i "
                                + "Förhandsvisning före HTML-export.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Exportera")
            .alert("Exporten misslyckades", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Okänt fel")
            }
        } else {
            ContentUnavailableView(
                "Inget panorama att exportera",
                systemImage: "square.and.arrow.up",
                description: Text("Generera panoramat först.")
            )
        }
    }

    private var defaultName: String {
        let candidate = projectName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return candidate.flatMap { $0.isEmpty ? nil : $0 }
            ?? model.project.title
    }

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(defaultName).html"
        panel.title = "Exportera interaktivt panorama"
        panel.prompt = "Exportera"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportHTML(to: url, initialViewpoint: viewpoint)
    }

    private func shareHTML() {
        isPreparingHTMLShare = true
        Task {
            do {
                let url = try await model.interactiveHTMLArchiveForSharing(
                    initialViewpoint: viewpoint
                )
                isPreparingHTMLShare = false
                guard let view = NSApp.keyWindow?.contentView else { return }
                // Mail may interpret a bare HTML document as message content
                // and rewrite it to a local file:// link. A ZIP is always
                // transferred as a real attachment.
                NSSharingServicePicker(items: [url as NSURL]).show(
                    relativeTo: view.bounds,
                    of: view,
                    preferredEdge: .minY
                )
            } catch {
                isPreparingHTMLShare = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func exportJPEG(from sourceURL: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(defaultName).jpg"
        panel.title = "Exportera panoramabild"
        panel.prompt = "Exportera"
        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }
        do {
            try Self.writeJPEG(
                from: sourceURL,
                to: destinationURL,
                maximumWidth: maximumWidth,
                quality: jpegQuality
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func writeJPEG(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumWidth: Int,
        quality: Double
    ) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        let image: CGImage?
        if maximumWidth > 0 {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumWidth,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image,
              let destination = CGImageDestinationCreateWithURL(
                  destinationURL as CFURL,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
