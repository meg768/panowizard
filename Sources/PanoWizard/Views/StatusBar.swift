import SwiftUI

struct StatusBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if model.phase == .importing || model.phase == .stitching {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
            }

            Text(model.phase.message)
                .lineLimit(1)

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
