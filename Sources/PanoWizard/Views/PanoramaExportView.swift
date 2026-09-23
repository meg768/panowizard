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
}

enum PanoramaImageFormat: String, CaseIterable {
    case jpeg = "JPEG"
    case png = "PNG"

    var contentType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        }
    }

    var filenameExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        }
    }
}

struct PanoramaExportView: View {
    @Bindable var model: AppModel
    @Bindable var controller: PanoramaExportController
    let projectName: String?
    let projectDirectoryURL: URL?
    @State private var isLittlePlanetPresented = false

    var body: some View {
        if let panoramaURL = model.currentPanoramaURL {
            Form {
                Section("Panorama Image") {
                    LabeledContent("Format", value: "Equirectangular · 2:1")
                    Picker("Size", selection: $controller.maximumWidth) {
                        Text("Original").tag(0)
                        Text("4096 px").tag(4_096)
                        Text("2048 px").tag(2_048)
                    }
                    Picker("JPEG Quality", selection: $controller.jpegQuality) {
                        Text("Normal").tag(0.82)
                        Text("High").tag(0.92)
                        Text("Maximum").tag(0.98)
                    }

                    HStack(spacing: 8) {
                        ForEach(
                            PanoramaImageFormat.allCases,
                            id: \.self
                        ) { format in
                            Button {
                                controller.exportImage(
                                    format: format,
                                    from: panoramaURL,
                                    nadirRetouchURL: model.nadirRetouchURL,
                                    zenithRetouchURL: model.zenithRetouchURL,
                                    projectName: projectName,
                                    projectTitle: model.project.title,
                                    projectDirectoryURL: projectDirectoryURL
                                )
                            } label: {
                                Label(
                                    "Save \(format.rawValue)…",
                                    systemImage: "square.and.arrow.down"
                                )
                            }
                        }
                    }
                    .buttonStyle(WorkspaceToolbarPillStyle())
                }

                Section("Interactive Panorama") {
                    Text(
                        "A self-contained HTML file that opens in a modern "
                            + "web browser without any additional files."
                    )
                    .foregroundStyle(.secondary)

                    Button {
                        controller.exportHTML(
                            model: model,
                            projectName: projectName,
                            projectDirectoryURL: projectDirectoryURL,
                            viewpoint: model.panoramaViewpoint
                        )
                    } label: {
                        Label(
                            "Save HTML…",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(WorkspaceToolbarPillStyle())
                    .disabled(!model.canExportHTML)
                }

                Section("Little Planet") {
                    Text("Create a Little Planet image from your panorama.")
                        .foregroundStyle(.secondary)

                    Button {
                        isLittlePlanetPresented = true
                    } label: {
                        Label(
                            "Create Little Planet…",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(WorkspaceToolbarPillStyle())
                }

            }
            .formStyle(.grouped)
            .sheet(isPresented: $isLittlePlanetPresented) {
                LittlePlanetExportSheet(
                    panoramaURL: panoramaURL,
                    nadirRetouchURL: model.nadirRetouchURL,
                    zenithRetouchURL: model.zenithRetouchURL,
                    projectName: projectName,
                    projectTitle: model.project.title,
                    projectDirectoryURL: projectDirectoryURL
                )
            }
            .alert("Export Failed", isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.errorMessage ?? "Unknown error")
            }
        } else {
            ContentUnavailableView {
                Label(
                    "No Panorama to Export",
                    systemImage: "square.and.arrow.up"
                )
            } description: {
                Text("Create the panorama to continue.")
            } actions: {
                Button {
                    model.stitch()
                } label: {
                    Text("Create")
                }
                .buttonStyle(WorkspaceToolbarPillStyle())
                .disabled(!model.canStitch)
                .help("Create a panorama with the current images and masks")
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
        panel.title = "Export Interactive Panorama"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportHTML(to: url, initialViewpoint: viewpoint)
    }

    func exportImage(
        format: PanoramaImageFormat,
        from sourceURL: URL,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        projectName: String?,
        projectTitle: String,
        projectDirectoryURL: URL?
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = projectDirectoryURL
        let name = defaultName(
            projectName: projectName,
            projectTitle: projectTitle
        )
        panel.nameFieldStringValue = "\(name).\(format.filenameExtension)"
        panel.title = "Save Panorama as \(format.rawValue)"
        panel.prompt = "Save"
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
                try Self.writeImage(
                    from: exportSourceURL,
                    to: destinationURL,
                    format: format,
                    maximumWidth: maximumWidth,
                    quality: quality
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func writeImage(
        from sourceURL: URL,
        to destinationURL: URL,
        format: PanoramaImageFormat,
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
                  format.contentType.identifier as CFString,
                  1,
                  nil
              ) else { throw CocoaError(.fileWriteUnknown) }
        let properties: CFDictionary?
        if format == .jpeg {
            properties = [
                kCGImageDestinationLossyCompressionQuality: quality
            ] as CFDictionary
        } else {
            properties = nil
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
