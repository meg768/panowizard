import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    let projectName: String?
    let projectDirectoryURL: URL?
    @State private var exportController = PanoramaExportController()
    @State private var retouchPatchPresentation: RetouchPatchPresentation?
    @State private var showsAdjustmentInspectorInPreview = false
    @State private var showsOriginalAdjustments = false
    @AppStorage("PanoWizard.ProjectWindow.sidebarWidth")
    private var savedSidebarWidth = 300.0

    var body: some View {
        ZStack {
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
                    NavigationSplitView(columnVisibility: .constant(.all)) {
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
                    .navigationSplitViewStyle(.balanced)
                    .toolbar(removing: .sidebarToggle)
                }
            }
            .disabled(retouchPatchPresentation != nil)

            if let presentation = retouchPatchPresentation {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                retouchPatchDialog(presentation)
                    .background(
                        .ultraThickMaterial,
                        in: RoundedRectangle(cornerRadius: 24)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.primary.opacity(0.22))
                    }
                    .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
                    .padding(18)
            }
        }
        .frame(
            minWidth: minimumContentWidth,
            minHeight: 600,
            alignment: .topLeading
        )
        .focusedSceneValue(
            \.panoramaCommandActions,
            PanoramaCommandActions(
                canOpenProjectViews: !model.project.images.isEmpty,
                canShowPanorama: model.stitchedResultURL != nil,
                canStitch: model.canStitch,
                createPanorama: model.stitch,
                showPreview: { model.selection = .panorama },
                showRetouch: { model.selection = .retouch },
                showExport: { model.selection = .export }
            )
        )
        .focusedSceneValue(
            \.imagesCommandActions,
            ImagesCommandActions(
                images: model.project.images.map { image in
                    ImageCommandItem(
                        id: image.id,
                        filename: image.filename,
                        isSelected: model.selectedSourceImage?.id == image.id
                    )
                },
                selectImage: model.selectSourceImage
            )
        )
        .focusedSceneValue(
            \.sourceMaskCommandActions,
            SourceMaskCommandActions(
                canUndo: model.canUndoMask,
                undo: model.undoMask
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
        .sheet(isPresented: stitchPresentation) {
            PanoramaStitchProgressSheet(model: model)
        }
        .onChange(of: model.selection) {
            showsOriginalAdjustments = false
        }
        .onChange(of: model.currentPanoramaURL) {
            guard model.currentPanoramaURL == nil else { return }
            showsAdjustmentInspectorInPreview = false
            showsOriginalAdjustments = false
        }
    }

    private var stitchPresentation: Binding<Bool> {
        Binding(
            get: { model.phase == .stitching },
            set: { isPresented in
                if !isPresented, model.phase == .stitching {
                    model.cancelStitch()
                }
            }
        )
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
                        presentPatch: { retouchPatchPresentation = $0 }
                    )
                } else {
                    previewWorkspace
                }
            }
        } status: {
            StatusBar(model: model)
        }
    }

    @ViewBuilder
    private func retouchPatchDialog(
        _ presentation: RetouchPatchPresentation
    ) -> some View {
        switch presentation.kind {
        case .ai:
            AIRetouchSheet(
                model: model,
                viewpoint: presentation.viewpoint,
                replacingPatch: presentation.replacingPatch,
                onDismiss: { retouchPatchPresentation = nil }
            )
        case .manual:
            ManualRetouchSheet(
                model: model,
                viewpoint: presentation.viewpoint,
                replacingPatch: presentation.replacingPatch,
                projectDirectoryURL: projectDirectoryURL,
                onDismiss: { retouchPatchPresentation = nil }
            )
        }
    }

    private var previewWorkspace: some View {
        HStack(spacing: 0) {
            PanoramaPreview(
                panorama: model.panorama,
                imageURL: model.selectedPreviewURL,
                isStitched: model.isShowingStitchedPanorama,
                adjustments: previewAdjustments,
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
                    model.setSourceMasks(red: red, green: green, for: image.id)
                }
            )
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

            if model.isShowingStitchedPanorama
                && showsAdjustmentInspectorInPreview {
                Divider()

                PanoramaAdjustPanel(
                    model: model,
                    showsOriginal: $showsOriginalAdjustments
                )
                .frame(width: 260)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(
            minWidth: isAdjustmentInspectorVisible ? 680 : 400,
            alignment: .leading
        )
    }

    private var isAdjustmentInspectorVisible: Bool {
        model.isShowingStitchedPanorama && showsAdjustmentInspectorInPreview
    }

    private var minimumContentWidth: CGFloat {
        isAdjustmentInspectorVisible ? 940 : 900
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
            if model.isShowingStitchedPanorama {
                Button {
                    toggleAdjustmentInspector()
                } label: {
                    Label("Adjustments", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(MaskToolbarButtonStyle(
                    isSelected: showsAdjustmentInspectorInPreview,
                    showsTitle: true
                ))
                .help("Show or hide panorama adjustments")
            }
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
                    model.sourceMaskIntent = .exclude
                } label: {
                    Label {
                        Text("Exclude")
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(MaskToolbarButtonStyle(
                    isSelected: model.sourceMaskIntent == .exclude,
                    showsTitle: true
                ))
                .help("Exclude")

                Button {
                    model.sourceMaskIntent = .protect
                } label: {
                    Label {
                        Text("Include")
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .buttonStyle(MaskToolbarButtonStyle(
                    isSelected: model.sourceMaskIntent == .protect,
                    showsTitle: true
                ))
                .help("Include")
            }

            maskToolbarDivider

            HStack(spacing: 2) {
                Button {
                    model.undoMask()
                } label: {
                    Label("Undo Mask Change", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(MaskToolbarButtonStyle())
                .disabled(!model.canUndoMask)
                .help("Undo mask change (⌘Z)")

                Button {
                    model.invertSelectedMask()
                } label: {
                    Label(
                        "Invert Current Mask",
                        systemImage: "circle.lefthalf.filled"
                    )
                }
                .buttonStyle(MaskToolbarButtonStyle())
                .disabled(selectedMaskData == nil)
                .help("Invert current mask")

                Button(role: .destructive) {
                    model.clearSelectedMask()
                } label: {
                    Label("Clear Current Mask", systemImage: "trash")
                }
                .buttonStyle(MaskToolbarButtonStyle())
                .disabled(selectedMaskData == nil)
                .help("Clear current mask")
            }

            maskToolbarDivider

            Button {
                guard let image = model.selectedSourceImage else { return }
                model.rotateSourceImageLeft(image.id)
            } label: {
                Label("Rotate Image Left", systemImage: "rotate.left")
            }
            .buttonStyle(MaskToolbarButtonStyle())
            .help("Rotate the image 90° counterclockwise")
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
        model.isShowingStitchedPanorama
            || model.selectedSourceImage != nil
    }

    private var previewAdjustments: PanoramaAdjustments {
        showsOriginalAdjustments && showsAdjustmentInspectorInPreview
            ? .neutral
            : model.panoramaAdjustments
    }

    private func toggleAdjustmentInspector() {
        guard model.currentPanoramaURL != nil else { return }
        showsAdjustmentInspectorInPreview.toggle()
        if !showsAdjustmentInspectorInPreview {
            showsOriginalAdjustments = false
        }
    }

}

private struct PanoramaStitchProgressSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.small)

            VStack(spacing: 4) {
                Text(model.stitchStage.isEmpty
                    ? "Creating panorama…"
                    : model.stitchStage)
                    .font(.headline)
                Text("This may take a few minutes.")
                    .foregroundStyle(.secondary)
            }

            Button("Cancel", role: .cancel) {
                model.cancelStitch()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 320)
        .interactiveDismissDisabled()
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
