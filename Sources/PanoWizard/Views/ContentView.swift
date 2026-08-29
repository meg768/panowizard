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
    @FocusedValue(\.controlPointCommandActions)
    private var controlPointActions
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
                showPanoramaSettings: { model.selection = .settings },
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
                if model.selection == .settings {
                    PanoramaSettingsView(model: model)
                } else if model.selection == .export {
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
                } else if model.selection == .controlPoints {
                    if let diagnostics = model.controlPointEditorDiagnostics,
                       diagnostics.images.count >= 2 {
                        let pairID = model.selectedControlPointPairID
                            ?? diagnostics.pairs.first?.id
                            ?? ControlPointPair.ID(firstImage: 0, secondImage: 1)
                        ControlPointEditor(
                            diagnostics: diagnostics,
                            selectedPairID: pairID,
                            leftImageIndex: model.controlPointLeftImageIndex,
                            rightImageIndex: model.controlPointRightImageIndex,
                            onSelectImages: model.selectControlPointImages,
                            onMovePoint: model.moveControlPoint,
                            onRemovePoint: model.removeControlPoint,
                            onAddPoint: { point, imageIndex in
                                model.addPredictedControlPoint(
                                    to: pairID,
                                    point: point,
                                    in: imageIndex
                                )
                            },
                            onPredictPoint: { point, imageIndex in
                                model.predictedControlPointCounterpart(
                                    to: pairID,
                                    point: point,
                                    in: imageIndex
                                )
                            },
                            isSuggestingPoints: model.isSuggestingControlPoints,
                            onSuggestPoints: {
                                model.suggestControlPoints(for: pairID)
                            },
                            onRegenerateProjectPoints: {
                                model.regenerateControlPointsForProject()
                            },
                            onRemoveAllPoints: {
                                model.removeAllControlPoints(in: pairID)
                            },
                            onRemoveAllProjectPoints: {
                                model.removeAllControlPoints()
                            },
                            onOptimize: model.optimizeEditedControlPoints,
                            isPoleAlignment: false
                        )
                    } else {
                        ContentUnavailableView(
                            "Minst två bilder behövs",
                            systemImage: "scope",
                            description: Text(
                                "Lägg till fler källbilder för att skapa kontrollpunkter."
                            )
                        )
                    }
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
            toolbarTrailing
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var toolbarCenter: some View {
        HStack(spacing: 6) {
            if model.selection == .controlPoints {
                controlPointToolbarCenter
            } else if model.selectedSourceImage != nil {
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

    @ViewBuilder
    private var controlPointToolbarCenter: some View {
        if let actions = controlPointActions {
            Button(action: actions.toggleAddingPoint) {
                Label(
                    actions.addPointTitle,
                    systemImage: actions.addPointTitle.hasPrefix("Avbryt")
                        ? "xmark" : "plus"
                )
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .help("Lägg till eller avbryt ny kontrollpunkt (⌥A)")

            Button(action: actions.suggestPairPoints) {
                Label("Föreslå punkter", systemImage: "sparkles")
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(!actions.canSuggest)
            .help(
                "Lägg till upp till "
                    + "\(AppModel.suggestedControlPointBatchSize) "
                    + "utspridda kontrollpunkter (⌥F)"
            )

            Button(action: actions.optimize) {
                Label(
                    actions.optimizeTitle,
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(!actions.canOptimize)
            .help("Optimera kontrollpunkterna (⌥O)")
        }
    }
    @ViewBuilder
    private var toolbarTrailing: some View {
        HStack(spacing: 6) {
            primaryToolbarAction

            if showsToolbarOverflow {
                toolbarOverflow
            }
        }
    }

    @ViewBuilder
    private var primaryToolbarAction: some View {
        if model.selectedSourceImage?.effectiveRole == .fillOnly,
           model.stitchedResultURL != nil {
            Button {
                model.showSelectedRepairPreview()
            } label: {
                Label("Visa resultat", systemImage: "checkmark.circle")
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(model.phase != .ready)
        }
    }

    private var toolbarOverflow: some View {
        Menu {
            if let actions = controlPointActions {
                Button("Generera om alla kontrollpunkter…") {
                    actions.requestRegenerateProjectPoints()
                }
                .disabled(!actions.canRegenerateProject)

                Divider()

                Button("Radera markerad punkt", role: .destructive) {
                    actions.removeSelectedPoint()
                }
                .disabled(!actions.canRemoveSelectedPoint)
                Button("Radera alla i aktuellt bildpar…", role: .destructive) {
                    actions.requestRemovePairPoints()
                }
                .disabled(!actions.canRemovePairPoints)
                Button(
                    "Radera alla kontrollpunkter i projektet…",
                    role: .destructive
                ) {
                    actions.requestRemoveProjectPoints()
                }
                .disabled(!actions.canRemoveProjectPoints)
            }
        } label: {
            Text("•••")
                .accessibilityLabel("Vymeny")
        }
        .menuStyle(.button)
        .buttonStyle(WorkspaceToolbarMenuStyle())
        .help("Vymeny")
    }

    private var showsToolbarOverflow: Bool {
        model.selection == .controlPoints && controlPointActions != nil
    }

    private var showsWorkspaceToolRow: Bool {
        model.selectedSourceImage != nil || showsToolbarOverflow
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

private struct PanoramaSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Objektiv") {
                if let detectedProfile = model.imageMetadataLensProfile {
                    LabeledContent("Objektivprofil") {
                        Text(detectedProfile.displayName)
                    }
                    LabeledContent("Källa") {
                        Text("Bildmetadata (EXIF)")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Objektivprofil", selection: lensProfile) {
                        ForEach(
                            StitchingConfiguration.LensProfile.selectableProfiles,
                            id: \.self
                        ) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    Text(
                        "Bildmetadata saknar ett identifierbart objektiv. "
                            + "Välj profil manuellt."
                    )
                    .foregroundStyle(.secondary)
                }

                LabeledContent("Horisontellt synfält") {
                    Text(
                        String(
                            format: "%.1f°",
                            model.project.stitching.inputHorizontalFieldOfView
                        )
                    )
                }
            }

            Section {
                Text(
                    "Roll och masker anges för varje källbild. För en "
                        + "reparationsbild avgör PanoWizard automatiskt om "
                        + "den hör till zenit eller nadir."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Panoramainställningar")
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private var lensProfile: Binding<StitchingConfiguration.LensProfile> {
        Binding(
            get: {
                model.project.stitching.lensProfile == .nikon105DX
                    ? .nikon105DX
                    : .sigma8DX
            },
            set: { value in
                model.updateStitchingConfiguration {
                    $0.lensProfile = value
                    if let fieldOfView = value.defaultHorizontalFieldOfView {
                        $0.inputHorizontalFieldOfView = fieldOfView
                    }
                }
            }
        )
    }
}
