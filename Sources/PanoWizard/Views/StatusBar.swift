import SwiftUI

struct StatusBar: View {
    let model: AppModel
    @State private var showsFailureDetails = false

    var body: some View {
        HStack(spacing: 12) {
            if model.phase == .importing
                || model.phase == .stitching
                || model.phase == .suggestingControlPoints
                || model.phase == .optimizingControlPoints
                || model.phase == .updatingRepair
                || model.phase == .blendingRepair
                || model.phase == .retouching
                || model.phase == .exporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
            }

            if let details = model.phase.failureDetails {
                Button {
                    showsFailureDetails = true
                } label: {
                    HStack(spacing: 6) {
                        Text(details.components(separatedBy: .newlines).first
                            ?? details)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("Visa orsak")
                            .foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
                .help("Visa fullständig felrapport och loggplats")
                .popover(isPresented: $showsFailureDetails) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Stitchningen misslyckades")
                            .font(.headline)
                        ScrollView {
                            Text(details)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("Stäng") {
                            showsFailureDetails = false
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    .padding(16)
                    .frame(width: 620, height: 360)
                }
            } else {
                Text(statusMessage)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(statusMessage)
            }

            Spacer()

            if !model.project.images.isEmpty {
                Text("\(model.project.images.count) bilder")
                    .foregroundStyle(.secondary)
            }

            if model.skippedFileCount > 0 {
                Text("\(model.skippedFileCount) kunde inte läsas")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .clipped()
        .background(.bar, ignoresSafeAreaEdges: [])
    }

    private var statusSymbol: String {
        if case .failed = model.phase { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if case .failed = model.phase { return .orange }
        return .green
    }

    private var statusMessage: String {
        if model.selection == .controlPoints,
           model.phase == .ready,
           let count = model.lastControlPointSuggestionCount {
            return count == 1
                ? "1 ny kontrollpunkt tillagd"
                : "\(count) nya kontrollpunkter tillagda"
        }
        guard model.phase == .ready,
              model.selectedSourceImage != nil,
              !model.isShowingStitchedPanorama else {
            return model.phase.message
        }
        let action: String
        if model.sourceMaskTool == .rectangle {
            action = "markerar ett rektangulärt område"
        } else if model.sourceMaskIntent == .erase {
            action = "suddar masken"
        } else if model.sourceMaskIntent == .protect {
            action = "målar en grön skyddsmask"
        } else {
            action = "målar en röd exkluderingsmask"
        }
        return "Dra panorerar · rulla zoomar · ⌘-dra \(action) · "
            + "⌘⌥-dra suddar"
    }
}
