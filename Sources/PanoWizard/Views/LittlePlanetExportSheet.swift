import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class LittlePlanetExportController {
    var settings = LittlePlanetSettings() {
        didSet { schedulePreview() }
    }
    var previewImage: NSImage?
    var errorMessage: String?
    var isLoading = true
    var isSaving = false

    private var source: LittlePlanetSource?
    private var previewTask: Task<Void, Never>?

    func load(
        sourceURL: URL,
        nadirOverlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        adjustments: PanoramaAdjustments
    ) {
        guard source == nil else { return }
        Task {
            do {
                source = try await Task.detached(priority: .userInitiated) {
                    try LittlePlanetSource(
                        panoramaURL: sourceURL,
                        nadirOverlayURL: nadirOverlayURL,
                        zenithOverlayURL: zenithOverlayURL,
                        nadirRetouchURL: nadirRetouchURL,
                        zenithRetouchURL: zenithRetouchURL,
                        adjustments: adjustments
                    )
                }.value
                isLoading = false
                schedulePreview()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func save(projectName: String?, projectTitle: String, directoryURL: URL?) {
        guard let source else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = directoryURL
        let trimmedName = projectName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let name = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? projectTitle
        panel.nameFieldStringValue = "\(name)-little-planet.png"
        panel.title = "Save Little Planet"
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let settings = settings
        isSaving = true
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let image = try LittlePlanetRenderer.render(
                        source: source,
                        side: source.height,
                        settings: settings
                    )
                    try LittlePlanetRenderer.writePNG(image, to: url)
                }.value
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func schedulePreview() {
        previewTask?.cancel()
        guard let source else { return }
        let settings = settings
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            do {
                let rendering = Task.detached(priority: .userInitiated) {
                    try LittlePlanetRenderer.render(
                        source: source,
                        side: 640,
                        settings: settings
                    )
                }
                let image = try await withTaskCancellationHandler {
                    try await rendering.value
                } onCancel: {
                    rendering.cancel()
                }
                guard !Task.isCancelled else { return }
                previewImage = NSImage(cgImage: image, size: .zero)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct LittlePlanetExportSheet: View {
    let panoramaURL: URL
    let nadirOverlayURL: URL?
    let zenithOverlayURL: URL?
    let nadirRetouchURL: URL?
    let zenithRetouchURL: URL?
    let adjustments: PanoramaAdjustments
    let projectName: String?
    let projectTitle: String
    let projectDirectoryURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var controller = LittlePlanetExportController()

    var body: some View {
        @Bindable var controller = controller
        VStack(spacing: 0) {
            HStack {
                Text("Create Little Planet")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            HStack(alignment: .top, spacing: 20) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Form {
                    Picker("Projection", selection: $controller.settings.projection) {
                        ForEach(LittlePlanetProjection.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.menu)

                    valueSlider(
                        "Rotation",
                        value: $controller.settings.rotationDegrees,
                        range: -180...180,
                        suffix: "°"
                    )

                    valueSlider(
                        "Zoom / Planet Size",
                        value: $controller.settings.zoomPercent,
                        range: 50...150,
                        suffix: "%"
                    )

                    valueSlider(
                        "Horizon Height",
                        value: $controller.settings.horizonPercent,
                        range: 25...75,
                        suffix: "%"
                    )

                    Picker("Background", selection: $controller.settings.background) {
                        ForEach(LittlePlanetBackground.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .formStyle(.grouped)
                .frame(width: 310)
                .disabled(controller.isLoading || controller.isSaving)
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…") {
                    controller.save(
                        projectName: projectName,
                        projectTitle: projectTitle,
                        directoryURL: projectDirectoryURL
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    controller.previewImage == nil
                        || controller.isLoading
                        || controller.isSaving
                )
            }
            .padding(16)
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 580, idealHeight: 640)
        .task {
            controller.load(
                sourceURL: panoramaURL,
                nadirOverlayURL: nadirOverlayURL,
                zenithOverlayURL: zenithOverlayURL,
                nadirRetouchURL: nadirRetouchURL,
                zenithRetouchURL: zenithRetouchURL,
                adjustments: adjustments
            )
        }
        .alert("Little Planet Failed", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let image = controller.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(12)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private func valueSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .lineLimit(1)
                Spacer()
                TextField(
                    "",
                    value: Binding(
                        get: { value.wrappedValue },
                        set: {
                            value.wrappedValue = min(
                                max($0, range.lowerBound),
                                range.upperBound
                            )
                        }
                    ),
                    format: .number.precision(.fractionLength(0))
                )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 68)
                    .onKeyPress(.upArrow) {
                        value.wrappedValue = min(
                            value.wrappedValue + 1,
                            range.upperBound
                        )
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        value.wrappedValue = max(
                            value.wrappedValue - 1,
                            range.lowerBound
                        )
                        return .handled
                    }
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Slider(value: value, in: range)
        }
    }
}
