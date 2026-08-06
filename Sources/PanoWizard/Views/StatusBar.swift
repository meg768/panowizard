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
                Text(model.phase.message)
                    .lineLimit(1)
                    .help(model.phase.message)
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
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var statusSymbol: String {
        if case .failed = model.phase { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if case .failed = model.phase { return .orange }
        return .green
    }
}
