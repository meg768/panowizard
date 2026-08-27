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
                        "Välj AI-retuschera i verktygsraden eller exportera "
                            + "den plana kubsidan och redigera den i ett "
                            + "externt bildprogram."
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

struct AIRetouchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let pole: PanoramaPole

    @State private var apiKey = ""
    @State private var prompt: String
    @State private var preview: AIRetouchPreview?
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var isWorking = false

    private let keyStore = OpenAIAPIKeyStore()

    init(model: AppModel, pole: PanoramaPole) {
        self.model = model
        self.pole = pole
        _prompt = State(
            initialValue: model.aiRetouchPrompt(for: pole)
                ?? Self.defaultPrompt(for: pole)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI-retuschera \(pole.displayName.lowercased())")
                    .font(.title2.bold())
                Text(
                    "Bilden skickas till OpenAI. Ingen retusch aktiveras "
                        + "förrän du väljer Använd."
                )
                .foregroundStyle(.secondary)
            }

            if let preview {
                HStack(alignment: .top, spacing: 16) {
                    AIRetouchImageCard(title: "Före", url: preview.sourceURL)
                    AIRetouchImageCard(title: "Efter", url: preview.editedURL)
                }
                .frame(maxHeight: .infinity)
            }

            GroupBox("Instruktion") {
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 82, maxHeight: 110)
                    .padding(6)
            }

            GroupBox("OpenAI") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("API-nyckel", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("Nyckeln sparas i macOS Nyckelring.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link(
                            "Hantera API-nycklar",
                            destination: URL(
                                string: "https://platform.openai.com/api-keys"
                            )!
                        )
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }

            if isWorking {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("OpenAI retuscherar bilden… Det kan ta upp till två minuter.")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Avbryt", role: .cancel) {
                    cancelAndDismiss()
                }
                Spacer()
                if preview != nil {
                    Button("Försök igen") {
                        generate()
                    }
                    .disabled(isWorking || !canGenerate)

                    Button("Använd") {
                        applyPreview()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
                } else {
                    Button("AI-retuschera") {
                        generate()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || !canGenerate)
                }
            }
        }
        .padding(22)
        .frame(
            minWidth: 760,
            idealWidth: 900,
            minHeight: preview == nil ? 460 : 720,
            idealHeight: preview == nil ? 500 : 780
        )
        .onAppear {
            apiKey = keyStore.load() ?? ""
        }
        .onDisappear {
            generationTask?.cancel()
            if let preview {
                model.discardAIRetouchPreview(preview)
            }
        }
    }

    private var canGenerate: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func generate() {
        errorMessage = nil
        model.setAIRetouchPrompt(prompt, for: pole)
        do {
            try keyStore.save(apiKey)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isWorking = true
        let oldPreview = preview
        generationTask?.cancel()
        generationTask = Task {
            defer { isWorking = false }
            do {
                let newPreview = try await model.createAIRetouchPreview(
                    for: pole,
                    prompt: prompt,
                    apiKey: apiKey
                )
                guard !Task.isCancelled else {
                    model.discardAIRetouchPreview(newPreview)
                    return
                }
                if let oldPreview {
                    model.discardAIRetouchPreview(oldPreview)
                }
                preview = newPreview
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyPreview() {
        guard let preview else { return }
        do {
            try model.applyAIRetouchPreview(preview)
            model.discardAIRetouchPreview(preview)
            self.preview = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelAndDismiss() {
        generationTask?.cancel()
        if let preview {
            model.discardAIRetouchPreview(preview)
            self.preview = nil
        }
        dismiss()
    }

    private static func defaultPrompt(for pole: PanoramaPole) -> String {
        let direction = pole == .nadir ? "nedåt" : "uppåt"
        return """
        Detta är en plan 90°-kubsida som tittar \(direction) i ett 360°-panorama. \
        Ta bort kamerastativ, monopod, fotografens skugga och eventuella svarta \
        hål. Återskapa det skymda underlaget fotorealistiskt. Bevara exakt \
        perspektiv, riktning och kontinuitet i golv, plankor, fogar och andra \
        linjer. Ändra inget annat i bilden.
        """
    }
}

private struct AIRetouchImageCard: View {
    let title: String
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Group {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView(
                        "Bilden kunde inte visas",
                        systemImage: "photo.badge.exclamationmark"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
