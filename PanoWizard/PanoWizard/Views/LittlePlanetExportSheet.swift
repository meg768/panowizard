import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LittlePlanetPanoramaSelection {
    static func clampedLocation(
        _ location: CGPoint,
        in size: CGSize
    ) -> CGPoint {
        CGPoint(
            x: min(max(location.x, 0), size.width),
            y: min(max(location.y, 0), size.height)
        )
    }

    static func sourceCoordinates(
        at location: CGPoint,
        viewportSize: CGSize
    ) -> (longitudeDegrees: Double, latitudeDegrees: Double) {
        let location = clampedLocation(location, in: viewportSize)
        let turn = Double(location.x / max(viewportSize.width, 1))
        return (
            (turn - floor(turn)) * 360,
            90 - Double(location.y / max(viewportSize.height, 1)) * 180
        )
    }

}

@MainActor
@Observable
final class LittlePlanetExportController {
    static let previewSide = 640

    var settings: LittlePlanetSettings

    init(settings: LittlePlanetSettings? = nil) {
        if let saved = settings,
           (0...100).contains(saved.horizonPercent),
           (-180...180).contains(saved.rotationDegrees),
           (-90...90).contains(saved.centerLatitudeDegrees),
           (0...360).contains(saved.centerLongitudeDegrees) {
            self.settings = saved
        } else {
            self.settings = LittlePlanetSettings()
        }
    }

    var panoramaImage: NSImage?
    var previewImage: NSImage?
    var errorMessage: String?
    var isLoading = true
    var isSaving = false
    var isInteracting = false

    var exportSide: Int? { source?.height }

    func reset() {
        settings = LittlePlanetSettings()
    }

    private var source: LittlePlanetSource?
    private var previewTask: Task<Void, Never>?

    func load(
        sourceURL: URL,
        adjustments: PanoramaAdjustments
    ) {
        guard source == nil else { return }
        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    let source = try LittlePlanetSource(
                        panoramaURL: sourceURL,
                        adjustments: adjustments
                    )
                    return (source, try source.makeImage())
                }.value
                source = loaded.0
                panoramaImage = NSImage(cgImage: loaded.1, size: .zero)
                isLoading = false
                renderPreview()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func save(
        directoryURL: URL?,
        onSuccess: @escaping (LittlePlanetSettings) -> Void
    ) {
        guard let source else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = directoryURL
        panel.nameFieldStringValue = "little-planet.png"
        panel.title = "Export Little Planet"
        panel.prompt = "Export"
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
                isSaving = false
                onSuccess(settings)
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    func renderPreview() {
        previewTask?.cancel()
        guard let source else { return }
        let settings = settings
        let previewSide = isInteracting ? 320 : Self.previewSide
        previewTask = Task {
            do {
                let rendering = Task.detached(priority: .userInitiated) {
                    try LittlePlanetRenderer.render(
                        source: source,
                        side: previewSide,
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
    let adjustments: PanoramaAdjustments
    let projectDirectoryURL: URL?
    let onExport: (LittlePlanetSettings) -> Void
    let onDismiss: () -> Void

    @State private var controller: LittlePlanetExportController

    init(
        panoramaURL: URL,
        adjustments: PanoramaAdjustments,
        projectDirectoryURL: URL?,
        lastExportSettings: LittlePlanetSettings?,
        onExport: @escaping (LittlePlanetSettings) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.panoramaURL = panoramaURL
        self.adjustments = adjustments
        self.projectDirectoryURL = projectDirectoryURL
        self.onExport = onExport
        self.onDismiss = onDismiss
        _controller = State(initialValue: LittlePlanetExportController(settings: lastExportSettings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create Little Planet").font(.title2.bold())
                Text("Adjust zoom, rotation and center while watching the preview.")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    planetPreview
                        .frame(width: 480, height: 480)
                        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(centerDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                controls.frame(width: 280)
            }

            Divider()
            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Reset") {
                    controller.reset()
                }
                .disabled(controller.isLoading || controller.isSaving)
                Spacer()
                if let side = controller.exportSide {
                    Text("PNG · \(side) × \(side) pixels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Export…") {
                    controller.save(directoryURL: projectDirectoryURL) { exportedSettings in
                        onExport(exportedSettings)
                        onDismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(controller.previewImage == nil || controller.isLoading || controller.isSaving)
            }
        }
        .padding(22)
        .frame(width: 828)
        .task { controller.load(sourceURL: panoramaURL, adjustments: adjustments) }
        .onChange(of: controller.settings) { controller.renderPreview() }
        .alert("Little Planet Failed", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? "Unknown error")
        }
    }

    private var centerDescription: String {
        if controller.settings.centerLatitudeDegrees == -90 {
            return "Ground in the center · sky around the planet"
        }
        if controller.settings.centerLatitudeDegrees == 90 {
            return "Sky in the center · ground around the tunnel"
        }
        return "Tilt 0° for a planet · 180° for a tunnel"
    }

    private var controls: some View {
        @Bindable var controller = controller
        return VStack(alignment: .leading, spacing: 18) {
            adjustmentSlider(
                "Zoom", value: $controller.settings.horizonPercent,
                range: 0...100, valueText: "\(Int(controller.settings.horizonPercent))%",
                low: "Smaller", high: "Larger"
            )
            adjustmentSlider(
                "Rotation", value: $controller.settings.rotationDegrees,
                range: -180...180, valueText: "\(Int(controller.settings.rotationDegrees))°",
                low: "−180°", high: "180°"
            )
            adjustmentSlider(
                "Tilt", value: Binding(
                    get: { controller.settings.centerLatitudeDegrees + 90 },
                    set: { controller.settings.centerLatitudeDegrees = $0 - 90 }
                ), range: 0...180,
                valueText: "\(Int(controller.settings.centerLatitudeDegrees + 90))°",
                low: "Planet", high: "Tunnel"
            )
            adjustmentSlider(
                "Center", value: $controller.settings.centerLongitudeDegrees,
                range: 0...360,
                valueText: "\(Int(controller.settings.centerLongitudeDegrees))°",
                low: "0°", high: "360°"
            )
            .help("Move the center horizontally in the panorama. Rotation turns the result around that center.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose a custom center").font(.subheadline.bold())
                panoramaPicker.frame(height: 140)
                Text("Click the panorama to set Tilt and Center together.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 510, alignment: .top)
        .disabled(controller.isLoading || controller.isSaving)
    }

    private func adjustmentSlider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>,
        valueText: String, low: String, high: String
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(valueText).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range) { editing in
                controller.isInteracting = editing
                if !editing { controller.renderPreview() }
            }
            .accessibilityLabel(title)
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var panoramaPicker: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = controller.panoramaImage {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .scaleEffect(y: -1)
                    Circle().fill(Color.accentColor).stroke(.white, lineWidth: 2)
                        .frame(width: 10, height: 10)
                        .position(
                            x: min(max(CGFloat(controller.settings.centerLongitudeDegrees / 360) * geometry.size.width, 6), geometry.size.width - 6),
                            y: min(max(CGFloat(0.5 - controller.settings.centerLatitudeDegrees / 180) * geometry.size.height, 6), geometry.size.height - 6)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(.black.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                let coordinates = LittlePlanetPanoramaSelection.sourceCoordinates(
                    at: value.location, viewportSize: geometry.size
                )
                controller.settings.centerLongitudeDegrees = coordinates.longitudeDegrees
                controller.settings.centerLatitudeDegrees = coordinates.latitudeDegrees
            })
            .accessibilityLabel("Panorama: click to choose the center of the result")
        }
    }

    @ViewBuilder
    private var planetPreview: some View {
        if let image = controller.previewImage {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            ProgressView().controlSize(.large)
        }
    }
}
