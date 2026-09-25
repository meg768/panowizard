import SwiftUI

struct PanoramaAdjustPanel: View {
    @Bindable var model: AppModel
    @Binding var showsOriginal: Bool
    @State private var expandedGroups: Set<String> = ["Light", "Color"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Adjustments")
                    .font(.headline)
                Spacer()
                Button("Reset All") {
                    model.resetPanoramaAdjustments()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(model.panoramaAdjustments.isNeutral)
            }
            .padding(16)

            Divider()

            Button {
                showsOriginal.toggle()
            } label: {
                Label("Original", systemImage: "circle.lefthalf.filled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .background(
                showsOriginal
                    ? Color.accentColor.opacity(0.16)
                    : Color.clear,
                in: Capsule()
            )
            .padding(16)
            .help("Compare with the unadjusted panorama")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    adjustmentGroup("Light") {
                        adjustmentSlider(
                            "Exposure",
                            keyPath: \.exposure,
                            range: -3...3,
                            step: 0.05,
                            format: { String(format: "%+.2f", $0) }
                        )
                        adjustmentSlider("Brightness", keyPath: \.brightness)
                        adjustmentSlider("Contrast", keyPath: \.contrast)
                        adjustmentSlider("Highlights", keyPath: \.highlights)
                        adjustmentSlider("Shadows", keyPath: \.shadows)
                        adjustmentSlider("Whites", keyPath: \.whites)
                        adjustmentSlider("Blacks", keyPath: \.blacks)
                    }

                    adjustmentGroup("Color") {
                        adjustmentSlider("Temperature", keyPath: \.temperature)
                        adjustmentSlider("Tint", keyPath: \.tint)
                        adjustmentSlider("Vibrance", keyPath: \.vibrance)
                        adjustmentSlider("Saturation", keyPath: \.saturation)
                    }

                }
                .padding(16)
            }
        }
    }

    private func adjustmentGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedGroups.contains(title) },
            set: { isExpanded in
                if isExpanded {
                    expandedGroups.insert(title)
                } else {
                    expandedGroups.remove(title)
                }
            }
        )) {
            VStack(spacing: 12) {
                content()
            }
            .padding(.top, 8)
        } label: {
            Text(title)
        }
        .fontWeight(.medium)
    }

    private func adjustmentSlider(
        _ title: String,
        keyPath: WritableKeyPath<PanoramaAdjustments, Double>,
        range: ClosedRange<Double> = -100...100,
        step: Double = 1,
        format: @escaping (Double) -> String = {
            String(format: "%+.0f", $0)
        }
    ) -> some View {
        let value = model.panoramaAdjustments[keyPath: keyPath]
        return VStack(spacing: 3) {
            HStack {
                Text(title)
                    .fontWeight(.regular)
                Spacer()
                Text(format(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    model.resetPanoramaAdjustment(keyPath)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(value == 0)
                .help("Reset (title)")
            }

            Slider(
                value: adjustmentBinding(
                    keyPath,
                    range: range,
                    step: step
                ),
                in: range
            )
        }
    }

    private func adjustmentBinding(
        _ keyPath: WritableKeyPath<PanoramaAdjustments, Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> Binding<Double> {
        Binding(
            get: { model.panoramaAdjustments[keyPath: keyPath] },
            set: { value in
                let rounded = (value / step).rounded() * step
                let clamped = min(max(rounded, range.lowerBound), range.upperBound)
                model.setPanoramaAdjustment(
                    keyPath,
                    to: clamped == 0 ? 0 : clamped
                )
            }
        )
    }
}
