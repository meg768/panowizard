import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct AIRetouchPresentation: Identifiable {
    let id = UUID()
    let pole: PanoramaPole
}

struct ContentView: View {
    @Bindable var model: AppModel
    let projectName: String?
    let projectDirectoryURL: URL?
    @State private var exportController = PanoramaExportController()
    @State private var retouchController = PanoramaRetouchController()
    @State private var aiRetouchPresentation: AIRetouchPresentation?
    @AppStorage("PanoWizard.ProjectWindow.sidebarWidth")
    private var savedSidebarWidth = 300.0

    var body: some View {
        Group {
            if model.project.images.isEmpty {
                PanoramaWelcomeView(
                    isImporting: model.phase == .importing,
                    chooseImages: {
                        model.isImporterPresented = true
                    },
                    openProject: nil
                )
            } else {
                NavigationSplitView {
                    PanoramaSidebar(model: model)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.width
                        } action: { width in
                            persistSidebarWidth(width)
                        }
                        .navigationSplitViewColumnWidth(
                            min: 220,
                            ideal: min(max(savedSidebarWidth, 220), 520),
                            max: 520
                        )
                } detail: {
                    detailWorkspace
                }
            }
        }
        .focusedSceneValue(
            \.panoramaCommandActions,
            PanoramaCommandActions(
                canOpenProjectViews: !model.project.images.isEmpty,
                canShowPanorama: model.stitchedResultURL != nil,
                canStitch: model.canStitch,
                createPanorama: model.stitch,
                showPreview: { model.selection = .panorama },
                showExport: { model.selection = .export }
            )
        )
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importURLs(urls)
            }
        }
        .fileDialogDefaultDirectory(model.sourceDirectoryURL)
        .sheet(item: $aiRetouchPresentation) { presentation in
            AIRetouchSheet(model: model, pole: presentation.pole)
        }
    }

    private var detailWorkspace: some View {
        DetailWorkspace(showsControls: showsWorkspaceToolRow) {
            workspaceToolRow
        } content: {
            ZStack {
                if model.selection == .export {
                    PanoramaExportView(
                        model: model,
                        controller: exportController,
                        projectName: projectName,
                        projectDirectoryURL: projectDirectoryURL
                    )
                } else if model.selection == .retouch {
                    PanoramaRetouchView(
                        model: model,
                        projectDirectoryURL: projectDirectoryURL,
                        controller: retouchController,
                        onAIRetouch: { pole in
                            aiRetouchPresentation = AIRetouchPresentation(
                                pole: pole
                            )
                        }
                    )
                } else {
                    PanoramaPreview(
                        panorama: model.panorama,
                        imageURL: model.selectedPreviewURL,
                        isStitched: model.isShowingStitchedPanorama,
                        nadirOverlayURL: model.nadirOverlayURL,
                        zenithOverlayURL: model.zenithOverlayURL,
                        nadirRetouchURL: model.nadirRetouchURL,
                        zenithRetouchURL: model.zenithRetouchURL,
                        selectedSource: model.selectedSourceImage,
                        maskData: model.selectedSourceImage.flatMap {
                            model.maskDataByImageID[$0.id]
                        },
                        protectedMaskData: model.selectedSourceImage.flatMap {
                            model.protectedMaskDataByImageID[$0.id]
                        },
                        maskTool: model.sourceMaskTool,
                        maskIntent: model.sourceMaskIntent,
                        initialViewpoint: model.panoramaViewpoint,
                        onViewpointChange: model.setPanoramaViewpoint,
                        onMasksChange: { red, green in
                            guard let image = model.selectedSourceImage else { return }
                            model.setSourceMasks(
                                red: red, green: green, for: image.id
                            )
                        }
                    )
                }
            }
        } status: {
            StatusBar(model: model)
        }
    }

    private func persistSidebarWidth(_ width: CGFloat) {
        let clampedWidth = min(max(Double(width), 220), 520)
        guard abs(savedSidebarWidth - clampedWidth) >= 1 else {
            return
        }
        savedSidebarWidth = clampedWidth
    }

    private var workspaceToolRow: some View {
        HStack(spacing: 6) {
            toolbarCenter
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var toolbarCenter: some View {
        HStack(spacing: 6) {
            if model.selectedSourceImage != nil {
                sourceMaskToolbarCenter
            }
        }
    }

    @ViewBuilder
    private var sourceMaskToolbarCenter: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                Button {
                    model.sourceMaskTool = .brush
                } label: {
                    Label("Pensel", systemImage: "paintbrush.pointed")
                }
                .buttonStyle(MaskToolbarButtonStyle(
                    isSelected: model.sourceMaskTool == .brush,
                    showsTitle: true
                ))
                .help("Pensel")

                Button {
                    model.sourceMaskTool = .rectangle
                } label: {
                    Label("Rektangel", systemImage: "rectangle.dashed")
                }
                .buttonStyle(MaskToolbarButtonStyle(
                    isSelected: model.sourceMaskTool == .rectangle,
                    showsTitle: true
                ))
                .help("Rektangel")
            }

            maskToolbarDivider

            HStack(spacing: 2) {
                Button {
                    model.sourceMaskIntent = .exclude
                } label: {
                    Label {
                        Text("Uteslut")
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(MaskToolbarButtonStyle(
                    isSelected: model.sourceMaskIntent == .exclude,
                    showsTitle: true
                ))
                .help("Uteslut")

                Button {
                    model.sourceMaskIntent = .protect
                } label: {
                    Label {
                        Text("Skydda")
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .buttonStyle(MaskToolbarButtonStyle(
                    isSelected: model.sourceMaskIntent == .protect,
                    showsTitle: true
                ))
                .help("Skydda")
            }

            maskToolbarDivider

            HStack(spacing: 2) {
                Button {
                    model.invertSelectedMask()
                } label: {
                    Label(
                        "Invertera aktuell mask",
                        systemImage: "circle.lefthalf.filled"
                    )
                }
                .buttonStyle(MaskToolbarButtonStyle())
                .disabled(selectedMaskData == nil)
                .help("Invertera aktuell mask")

                Button(role: .destructive) {
                    model.clearSelectedMask()
                } label: {
                    Label("Nollställ aktuell mask", systemImage: "trash")
                }
                .buttonStyle(MaskToolbarButtonStyle())
                .disabled(selectedMaskData == nil)
                .help("Nollställ aktuell mask")
            }
        }
    }

    private var maskToolbarDivider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 3)
    }

    private var selectedMaskData: Data? {
        guard let image = model.selectedSourceImage else { return nil }
        return model.maskData(for: image.id)
    }

    private var showsWorkspaceToolRow: Bool {
        model.selectedSourceImage != nil
    }

}

private struct MaskToolbarButtonStyle: ButtonStyle {
    var isSelected = false
    var showsTitle = false

    func makeBody(configuration: Configuration) -> some View {
        MaskToolbarButtonBody(
            configuration: configuration,
            isSelected: isSelected,
            showsTitle: showsTitle
        )
    }
}

private struct MaskToolbarButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isSelected: Bool
    let showsTitle: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        styledLabel
            .foregroundStyle(.primary)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(isEnabled ? 1 : 0.42)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private var styledLabel: some View {
        if showsTitle {
            configuration.label
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 32)
        } else {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
        }
    }

    private var cornerRadius: CGFloat {
        showsTitle ? 16 : 6
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.primary.opacity(0.18)
        }
        if isSelected {
            return Color.primary.opacity(0.14)
        }
        return Color.primary.opacity(isHovering ? 0.1 : 0.055)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.primary.opacity(0.3)
        }
        return Color.primary.opacity(isHovering ? 0.24 : 0.12)
    }
}
