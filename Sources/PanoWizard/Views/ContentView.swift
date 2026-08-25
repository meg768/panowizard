import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    let projectName: String?
    let projectDirectoryURL: URL?
    @State private var exportController = PanoramaExportController()
    @State private var retouchController = PanoramaRetouchController()
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
                showSettings: { model.selection = .settings },
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
    }

    private var detailWorkspace: some View {
        DetailWorkspace {
            workspaceToolRow
        } content: {
            ZStack {
                if model.selection == .settings {
                    PanoramaSettingsView(model: model)
                } else if model.selection == .export {
                    PanoramaExportView(
                        model: model,
                        controller: exportController
                    )
                } else if case .retouch(let pole) = model.selection {
                    PanoramaRetouchView(model: model, pole: pole)
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
                        nadirOverlayURL: model.isShowingNadirRepair
                            ? model.nadirOverlayURL
                            : nil,
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
                        isAdjustingNadir: model.isAdjustingNadir,
                        adjustedPole: model.activeRepairPole,
                        nadirAdjustment: model.displayedNadirAdjustment,
                        nadirContentBounds: model.nadirContentBounds,
                        initialViewpoint: model.panoramaViewpoint,
                        onNadirAdjustmentChange: model.setNadirAdjustment,
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
            if model.selection == .export {
                exportToolbarCenter
            } else if case .retouch(let pole) = model.selection {
                retouchToolbarCenter(pole)
            } else if model.selection == .controlPoints {
                controlPointToolbarCenter
            } else if model.isShowingNadirRepair {
                repairToolbarCenter
            } else if model.selectedSourceImage != nil {
                sourceMaskToolbarCenter
            }
        }
    }

    @ViewBuilder
    private var exportToolbarCenter: some View {
        if let panoramaURL = model.stitchedResultURL {
            Button {
                exportController.exportJPEG(
                    from: panoramaURL,
                    nadirRetouchURL: model.nadirRetouchURL,
                    zenithRetouchURL: model.zenithRetouchURL,
                    projectName: projectName,
                    projectTitle: model.project.title,
                    projectDirectoryURL: projectDirectoryURL
                )
            } label: {
                Label("Spara JPEG…", systemImage: "photo")
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .help("Spara panoramabilden med valda inställningar")
        }
    }

    @ViewBuilder
    private func retouchToolbarCenter(_ pole: PanoramaPole) -> some View {
        if model.stitchedResultURL != nil {
            Button {
                retouchController.exportPlate(
                    model: model,
                    pole: pole,
                    projectDirectoryURL: projectDirectoryURL
                )
            } label: {
                Label("Exportera 90°-platta…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(model.phase != .ready)

            Button {
                retouchController.importPlate(model: model, pole: pole)
            } label: {
                Label("Importera retusch…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(model.phase != .ready)
        }
    }

    @ViewBuilder
    private var sourceMaskToolbarCenter: some View {
        Menu {
            Button("Pensel") {
                model.sourceMaskTool = .brush
            }
            Button("Rektangel") {
                model.sourceMaskTool = .rectangle
            }
        } label: {
            Label(
                model.sourceMaskTool == .brush ? "Pensel" : "Rektangel",
                systemImage: model.sourceMaskTool == .brush
                    ? "paintbrush.pointed" : "rectangle"
            )
        }
        .menuStyle(.button)
        .buttonStyle(WorkspaceToolbarPillStyle())
        .help("Välj hur masken ska målas")

        Menu {
            Button("Uteslut ur panoramat") {
                model.sourceMaskIntent = .exclude
            }
            Button("Skydda i panoramat") {
                model.sourceMaskIntent = .protect
            }
            Button("Sudda mask") {
                model.sourceMaskIntent = .erase
            }
        } label: {
            Label(maskIntentTitle, systemImage: maskIntentSystemImage)
        }
        .menuStyle(.button)
        .buttonStyle(WorkspaceToolbarPillStyle())
        .help("Välj vad masken ska göra")
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
    private var repairToolbarCenter: some View {
        if model.isAdjustingNadir {
            Button {
                model.resetNadirAdjustment()
            } label: {
                Label("Återställ position", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(model.displayedNadirAdjustment.isIdentity)
        } else {
            Menu {
                if model.zenithOverlayURL != nil {
                    Button("Justera zenit") {
                        model.beginRepairAdjustment(.zenith)
                    }
                }
                if model.nadirOverlayURL != nil {
                    Button("Justera nadir") {
                        model.beginRepairAdjustment(.nadir)
                    }
                }
            } label: {
                Label("Justera", systemImage: "move.3d")
            }
            .menuStyle(.button)
            .buttonStyle(WorkspaceToolbarPillStyle())

            Button {
                model.selectNadirRepairForMasking()
            } label: {
                Label(
                    model.hasNadirRepairMask
                        ? "Redigera mask" : "Maskera reparation",
                    systemImage: "paintbrush.pointed"
                )
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(model.phase != .ready)
            .help("Välj vilka delar av reparationsbilden som ska användas")
        }
    }

    @ViewBuilder
    private var toolbarTrailing: some View {
        HStack(spacing: 6) {
            primaryToolbarAction

            if model.selection != .export && hasStitchableSources {
                Button {
                    model.stitch()
                } label: {
                    Label("Skapa panorama", systemImage: "pano")
                }
                .buttonStyle(WorkspaceToolbarPillStyle())
                .disabled(!model.canStitch)
                .help(
                    "Skapa panorama med aktuella kontrollpunkter och masker"
                )
                .layoutPriority(1)
            }

            if showsToolbarOverflow {
                toolbarOverflow
            }
        }
    }

    @ViewBuilder
    private var primaryToolbarAction: some View {
        if model.isShowingNadirRepair && model.isAdjustingNadir {
            Button {
                model.toggleNadirAdjustment()
            } label: {
                Label("Förhandsvisa", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(model.phase != .ready)
        } else if model.selectedSourceImage?.effectiveRole == .fillOnly,
                  model.stitchedResultURL != nil {
            Button {
                model.showNadirRepairPreview()
            } label: {
                Label("Visa resultat", systemImage: "checkmark.circle")
            }
            .buttonStyle(WorkspaceToolbarPillStyle())
            .disabled(model.phase != .ready)
        }
    }

    private var toolbarOverflow: some View {
        Menu {
            if model.selection == .export,
               let panoramaURL = model.stitchedResultURL {
                Button("Dela JPEG…") {
                    exportController.shareJPEG(
                        sourceURL: panoramaURL,
                        nadirRetouchURL: model.nadirRetouchURL,
                        zenithRetouchURL: model.zenithRetouchURL
                    )
                }

                Divider()

                Button("Spara HTML…") {
                    exportController.exportHTML(
                        model: model,
                        projectName: projectName,
                        projectDirectoryURL: projectDirectoryURL,
                        viewpoint: model.panoramaViewpoint
                    )
                }
                .disabled(!model.canExportHTML)
                Button(
                    exportController.isPreparingHTMLShare
                        ? "Förbereder HTML…"
                        : "Dela HTML (.zip)…"
                ) {
                    exportController.shareHTML(
                        model: model,
                        viewpoint: model.panoramaViewpoint
                    )
                }
                .disabled(
                    !model.canExportHTML
                        || exportController.isPreparingHTMLShare
                )
            } else if case .retouch(let pole) = model.selection {
                Button(
                    "Ta bort \(pole.displayName.lowercased())retusch",
                    role: .destructive
                ) {
                    model.removeRetouch(for: pole)
                }
                .disabled(model.retouchURL(for: pole) == nil)
            } else if model.selection == .controlPoints,
               let actions = controlPointActions {
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
            } else {
                if let image = model.selectedSourceImage {
                    Button("Invertera aktuell mask") {
                        model.invertSelectedMask()
                    }
                    .disabled(model.maskData(for: image.id) == nil)
                    Button("Nollställ aktuell mask", role: .destructive) {
                        model.clearSelectedMask()
                    }
                    .disabled(model.maskData(for: image.id) == nil)

                }

            }
        } label: {
            Text("•••")
                .accessibilityLabel("Vymeny")
        }
        .menuStyle(.button)
        .buttonStyle(WorkspaceToolbarMenuStyle())
        .help("Vymeny")
    }

    private var hasStitchableSources: Bool {
        model.project.images.filter {
            $0.isEnabled && $0.effectiveRole == .alignment
        }.count >= 2
    }

    private var showsToolbarOverflow: Bool {
        if model.selection == .export {
            return model.stitchedResultURL != nil
        }
        if case .retouch(let pole) = model.selection {
            return model.retouchURL(for: pole) != nil
        }
        if model.selection == .controlPoints {
            return controlPointActions != nil
        }
        return model.selectedSourceImage != nil
    }

    private var maskIntentTitle: String {
        switch model.sourceMaskIntent {
        case .exclude: "Uteslut"
        case .protect: "Skydda"
        case .erase: "Sudda"
        }
    }

    private var maskIntentSystemImage: String {
        switch model.sourceMaskIntent {
        case .exclude: "eye.slash"
        case .protect: "shield"
        case .erase: "eraser"
        }
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
