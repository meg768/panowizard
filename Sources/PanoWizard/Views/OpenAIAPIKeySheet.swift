import SwiftUI

struct OpenAIAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var apiKey = ""
    @State private var errorMessage: String?

    private let keyStore = OpenAIAPIKeyStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("OpenAI API-nyckel")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "AI-retuscheringen använder OpenAI API. För att använda "
                        + "funktionen behöver du en egen API-nyckel från "
                        + "OpenAI. API-användningen debiteras separat av "
                        + "OpenAI och ingår inte i ChatGPT- eller "
                        + "Codex-abonnemang."
                )
                Text(
                    "Har du redan en API-nyckel klistrar du in den nedan. "
                        + "Annars öppnar du OpenAI, loggar in, skapar en ny "
                        + "secret key och kopierar den hit."
                )
            }
            .foregroundStyle(.secondary)

            Link(
                "Öppna OpenAI API-nycklar…",
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
                Button("Avbryt", role: .cancel) {
                    dismiss()
                }
                Button("Spara") {
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
