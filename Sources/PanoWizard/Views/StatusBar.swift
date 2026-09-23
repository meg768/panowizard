import SwiftUI

struct StatusBar: View {
    let model: AppModel
    @State private var showsFailureDetails = false

    var body: some View {
        HStack(spacing: 12) {
            if model.phase != .stitching {
                if model.phase == .importing
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
                            Text("Show Details")
                                .foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Show the full error report and log location")
                    .popover(isPresented: $showsFailureDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The Operation Failed")
                                .font(.headline)
                            ScrollView {
                                Text(details)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button("Close") {
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
            }

            Spacer()

            if !model.project.images.isEmpty {
                Text("\(model.project.images.count) images")
                    .foregroundStyle(.secondary)
            }

            if model.skippedFileCount > 0 {
                Text("\(model.skippedFileCount) could not be read")
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
        if (model.lastStitchHoleCount ?? 0) > 0 {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if case .failed = model.phase { return .orange }
        if (model.lastStitchHoleCount ?? 0) > 0 { return .orange }
        return .green
    }

    private var statusMessage: String {
        if model.phase == .ready,
           let coverage = model.lastStitchCoverage,
           let holes = model.lastStitchHoleCount {
            if holes > 0 {
                return String(
                    format: "Panorama complete · %.2f %% coverage · %d pixels lack unmasked source data",
                    coverage,
                    holes
                )
            }
            return model.usedAlignmentCache
                ? "Panorama complete · 100% coverage · alignment cache used"
                : "Panorama complete · 100% coverage"
        }
        guard model.phase == .ready,
              model.selectedSourceImage != nil,
              !model.isShowingStitchedPanorama else {
            return model.phase.message
        }
        guard model.isSourceMaskEditing else {
            return "Drag to pan · scroll to zoom"
        }
        let action: String
        if model.sourceMaskTool == .rectangle {
            action = "selects a rectangular area"
        } else if model.sourceMaskIntent == .erase {
            action = "erases the mask"
        } else if model.sourceMaskIntent == .protect {
            action = "paints a green protection mask"
        } else {
            action = "paints a red exclusion mask"
        }
        return "Drag to pan · scroll to zoom · ⌘-drag \(action) · "
            + "⌘⌥-drag erases"
    }
}
