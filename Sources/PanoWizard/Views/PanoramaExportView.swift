import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class PanoramaExportController {
    var jpegQuality = 0.92
    var maximumWidth = 0
    var errorMessage: String?
    var isPreparingHTMLShare = false
}

struct PanoramaExportView: View {
    @Bindable var model: AppModel
    @Bindable var controller: PanoramaExportController

    var body: some View {
        if model.stitchedResultURL != nil {
            Form {
                Section("Panoramabild") {
                    LabeledContent("Format", value: "Equirektangulär JPEG · 2:1")
                    Picker("Storlek", selection: $controller.maximumWidth) {
                        Text("Original").tag(0)
                        Text("4096 px").tag(4_096)
                        Text("2048 px").tag(2_048)
                    }
                    Picker("Kvalitet", selection: $controller.jpegQuality) {
                        Text("Normal").tag(0.82)
                        Text("Hög").tag(0.92)
                        Text("Maximal").tag(0.98)
                    }
                }

                Section("Interaktivt panorama") {
                    Text(
                        "En självständig HTML-fil som kan öppnas i en modern "
                            + "webbläsare utan andra tillhörande filer."
                    )
                    .foregroundStyle(.secondary)
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
            .alert("Exporten misslyckades", isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.errorMessage ?? "Okänt fel")
            }
        } else {
            ContentUnavailableView {
                Label(
                    "Inget panorama att exportera",
                    systemImage: "square.and.arrow.up"
                )
            } description: {
                Text("Generera panoramat för att fortsätta.")
            } actions: {
                Button {
                    model.stitch()
                } label: {
                    Text("Generera")
                }
                .buttonStyle(WorkspaceToolbarPillStyle())
                .disabled(!model.canStitch)
                .help("Skapa panorama med nuvarande kontrollpunkter och masker")
            }
        }
    }

}

extension PanoramaExportController {
    private func defaultName(
        projectName: String?,
        projectTitle: String
    ) -> String {
        let candidate = projectName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return candidate.flatMap { $0.isEmpty ? nil : $0 }
            ?? projectTitle
    }

    func exportHTML(
        model: AppModel,
        projectName: String?,
        projectDirectoryURL: URL?,
        viewpoint: PanoramaViewpoint
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = projectDirectoryURL
        let name = defaultName(
            projectName: projectName,
            projectTitle: model.project.title
        )
        panel.nameFieldStringValue = "\(name).html"
        panel.title = "Exportera interaktivt panorama"
        panel.prompt = "Exportera"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportHTML(to: url, initialViewpoint: viewpoint)
    }

    func shareHTML(model: AppModel, viewpoint: PanoramaViewpoint) {
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

    func shareJPEG(
        sourceURL: URL,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?
    ) {
        Task {
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appending(path: "PanoWizard/Exports", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let intermediateURL = directory.appending(
                    path: "\(UUID().uuidString)-retouched-panorama.png"
                )
                let shareURL = directory.appending(
                    path: "\(UUID().uuidString)-panorama.jpg"
                )
                let exportSourceURL: URL
                if nadirRetouchURL != nil || zenithRetouchURL != nil {
                    try await Task.detached(priority: .userInitiated) {
                        try PoleRetouchService().flattenRetouches(
                            panoramaURL: sourceURL,
                            nadirRetouchURL: nadirRetouchURL,
                            zenithRetouchURL: zenithRetouchURL,
                            to: intermediateURL
                        )
                    }.value
                    exportSourceURL = intermediateURL
                } else {
                    exportSourceURL = sourceURL
                }
                try Self.writeJPEG(
                    from: exportSourceURL,
                    to: shareURL,
                    maximumWidth: maximumWidth,
                    quality: jpegQuality
                )
                try? FileManager.default.removeItem(at: intermediateURL)
                guard let view = NSApp.keyWindow?.contentView else { return }
                NSSharingServicePicker(items: [shareURL as NSURL]).show(
                    relativeTo: view.bounds,
                    of: view,
                    preferredEdge: .minY
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func exportJPEG(
        from sourceURL: URL,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        projectName: String?,
        projectTitle: String,
        projectDirectoryURL: URL?
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = projectDirectoryURL
        let name = defaultName(
            projectName: projectName,
            projectTitle: projectTitle
        )
        panel.nameFieldStringValue = "\(name).jpg"
        panel.title = "Exportera panoramabild"
        panel.prompt = "Exportera"
        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }
        let maximumWidth = maximumWidth
        let quality = jpegQuality
        Task {
            do {
                let exportSourceURL: URL
                if nadirRetouchURL != nil || zenithRetouchURL != nil {
                    let temporaryURL = FileManager.default.temporaryDirectory
                        .appending(path: "\(UUID().uuidString)-retouched-panorama.png")
                    try await Task.detached(priority: .userInitiated) {
                        try PoleRetouchService().flattenRetouches(
                            panoramaURL: sourceURL,
                            nadirRetouchURL: nadirRetouchURL,
                            zenithRetouchURL: zenithRetouchURL,
                            to: temporaryURL
                        )
                    }.value
                    exportSourceURL = temporaryURL
                } else {
                    exportSourceURL = sourceURL
                }
                defer {
                    if exportSourceURL != sourceURL {
                        try? FileManager.default.removeItem(at: exportSourceURL)
                    }
                }
                try Self.writeJPEG(
                    from: exportSourceURL,
                    to: destinationURL,
                    maximumWidth: maximumWidth,
                    quality: quality
                )
            } catch {
                errorMessage = error.localizedDescription
            }
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
