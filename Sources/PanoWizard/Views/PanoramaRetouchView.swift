import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PanoramaRetouchController {
    func exportPlate(
        model: AppModel,
        pole: PanoramaPole,
        projectDirectoryURL: URL?
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = projectDirectoryURL
        panel.nameFieldStringValue = pole == .nadir ? "nadir.png" : "zenit.png"
        panel.title = "Exportera \(pole.displayName.lowercased())platta för retusch"
        panel.prompt = "Exportera"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportRetouchPlate(for: pole, to: url)
    }

    func importPlate(model: AppModel, pole: PanoramaPole) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Importera retuscherad \(pole.displayName.lowercased())platta"
        panel.prompt = "Importera"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importRetouchPlate(for: pole, from: url)
    }
}

struct PanoramaRetouchView: View {
    @Bindable var model: AppModel
    let pole: PanoramaPole

    var body: some View {
        if model.stitchedResultURL != nil {
            Form {
                Section("\(pole.displayName) · 90° kubsida") {
                    LabeledContent(
                        "Format",
                        value: "PNG · 2048 × 2048 px"
                    )
                    LabeledContent(
                        "Status",
                        value: model.retouchURL(for: pole) == nil
                            ? "Ingen importerad retusch"
                            : "Retusch aktiv"
                    )
                }

                Section("Arbetsflöde") {
                    Text(
                        "Exportera den plana kubsidan och redigera den i ett "
                            + "externt bildprogram. Behåll pixelmåttet och "
                            + "importera sedan PNG-filen igen."
                    )
                    Text(
                        "Retuschen sparas separat i projektet och ändrar inte "
                            + "källbilder, kontrollpunkter eller panoramageometri."
                    )
                    .foregroundStyle(.secondary)
                }

                if model.retouchURL(for: pole) != nil {
                    Section {
                        Label(
                            "Den importerade plattan visas ovanpå den vanliga "
                                + "\(pole.displayName.lowercased())reparationen.",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView {
                Label(
                    "Inget panorama att retuschera",
                    systemImage: "paintbrush.pointed"
                )
            } description: {
                Text("Generera panoramat för att skapa plana polsidor.")
            } actions: {
                Button("Generera") {
                    model.stitch()
                }
                .buttonStyle(WorkspaceToolbarPillStyle())
                .disabled(!model.canStitch)
            }
        }
    }
}
