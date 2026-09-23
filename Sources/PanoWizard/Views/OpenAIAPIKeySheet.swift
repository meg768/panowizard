import SwiftUI

struct OpenAIAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var apiKey = ""
    @State private var errorMessage: String?

    private let keyStore = OpenAIAPIKeyStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("OpenAI API Key")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "AI retouching uses the OpenAI API. To use this feature, "
                        + "you need your own OpenAI API key. API usage is "
                        + "billed separately by OpenAI and is not included in "
                        + "a ChatGPT or Codex subscription."
                )
                Text(
                    "If you already have an API key, paste it below. "
                        + "Otherwise, open OpenAI, sign in, create a new "
                        + "secret key, and copy it here."
                )
            }
            .foregroundStyle(.secondary)

            Link(
                "Open OpenAI API Keys…",
                destination: URL(string: "https://platform.openai.com/api-keys")!
            )

            TextEditor(text: $apiKey)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72, idealHeight: 88, maxHeight: 110)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 1)
                }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540)
        .onAppear {
            apiKey = keyStore.load() ?? ""
        }
    }

    private func save() {
        do {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try keyStore.remove()
            } else {
                try keyStore.save(trimmed)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
