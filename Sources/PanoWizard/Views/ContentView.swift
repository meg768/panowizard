import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    let projectName: String?
    let projectDirectoryURL: URL?
    @State private var isDropTargeted = false
    @AppStorage("PanoWizard.ProjectWindow.sidebarWidth")
    private var savedSidebarWidth = 300.0

    var body: some View {
        NavigationSplitView {
            PanoramaSidebar(model: model)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    let clampedWidth = min(max(Double(width), 220), 520)
                    guard abs(savedSidebarWidth - clampedWidth) >= 1 else {
                        return
                    }
                    savedSidebarWidth = clampedWidth
                }
                .navigationSplitViewColumnWidth(
                    min: 220,
                    ideal: min(max(savedSidebarWidth, 220), 520),
                    max: 520
                )
        } detail: {
            ZStack {
                if model.selection == .settings {
                    PanoramaSettingsView(model: model)
                } else if model.selection == .export {
                    PanoramaExportView(
                        model: model,
                        projectName: projectName,
                        projectDirectoryURL: projectDirectoryURL,
                        viewpoint: model.panoramaViewpoint
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
                            onSuggestProjectPoints: {
                                model.suggestControlPointsForProject()
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
                        selectedSource: model.selectedSourceImage,
                        maskData: model.selectedSourceImage.flatMap {
                            model.maskDataByImageID[$0.id]
                        },
                        protectedMaskData: model.selectedSourceImage.flatMap {
                            model.protectedMaskDataByImageID[$0.id]
                        },
                        controlPointMaskData: model.selectedSourceImage.flatMap {
                            model.controlPointMaskDataByImageID[$0.id]
                        },
                        maskTool: model.sourceMaskTool,
                        zoom: model.sourceImageZoom,
                        maskIntent: model.sourceMaskIntent,
                        isAdjustingNadir: model.isAdjustingNadir,
                        adjustedPole: model.activeRepairPole,
                        nadirAdjustment: model.displayedNadirAdjustment,
                        nadirContentBounds: model.nadirContentBounds,
                        initialViewpoint: model.panoramaViewpoint,
                        onNadirAdjustmentChange: model.setNadirAdjustment,
                        onViewpointChange: model.setPanoramaViewpoint,
                        onSourceZoomChange: { model.sourceImageZoom = $0 },
                        onMasksChange: { red, green, orange in
                            guard let image = model.selectedSourceImage else { return }
                            model.setSourceMasks(
                                red: red, green: green, orange: orange,
                                for: image.id
                            )
                        }
                    )
                }
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.tint.opacity(0.08))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                        .padding(20)
                        .allowsHitTesting(false)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBar(model: model)
            }
        }
        .focusedSceneValue(
            \.panoramaCommandActions,
            PanoramaCommandActions(
                canOpenProjectViews: !model.project.images.isEmpty,
                canShowPanorama: model.stitchedResultURL != nil,
                canStitch: model.canStitch,
                createPanorama: model.stitch,
                restartAutomatically: model.runWizard,
                showSettings: { model.selection = .settings },
                showPreview: { model.selection = .panorama },
                showExport: { model.selection = .export }
            )
        )
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.isImporterPresented = true
                } label: {
                    Label("Importera", systemImage: "plus")
                }

                if model.selection != .controlPoints {
                    Button {
                        model.stitch()
                    } label: {
                        Label(
                            "Skapa panorama",
                            systemImage: "rectangle.on.rectangle"
                        )
                    }
                    .disabled(!model.canStitch)
                    .help(
                        "Rendera med exakt de kontrollpunkter som finns nu"
                    )

                    Button {
                        model.runWizard()
                    } label: {
                        Label(
                            "Börja om automatiskt",
                            systemImage: "wand.and.stars"
                        )
                    }
                    .disabled(!model.canStitch)
                    .help(
                        "Radera gamla kontrollpunkter och skapa, optimera och "
                            + "rendera allt från grunden"
                    )
                }

                if model.selectedSourceImage != nil {
                    Menu {
                        if let image = model.selectedSourceImage {
                            Button {
                                model.setRole(.alignment, for: image.id)
                            } label: {
                                Label(
                                    "Ingår i positionering",
                                    systemImage: image.role == .alignment
                                        ? "checkmark" : "scope"
                                )
                            }
                            Divider()
                            ForEach(
                                SourceImage.Direction.repairCases,
                                id: \.self
                            ) { direction in
                                Button {
                                    model.setRepairArea(direction, for: image.id)
                                } label: {
                                    Label(
                                        "\(direction.displayName) · Reparation",
                                        systemImage: image.role == .fillOnly
                                            && image.direction == direction
                                            ? "checkmark"
                                            : "square.2.layers.3d.bottom.filled"
                                    )
                                }
                            }
                        }
                    } label: {
                        Label(
                            "Bildegenskaper",
                            systemImage: model.selectedSourceImage?.role == .fillOnly
                                ? repairAreaSymbol
                                : "scope"
                        )
                    }
                    .help("Ange bildens roll och reparationsområde")

                    Picker("Verktyg", selection: $model.sourceMaskTool) {
                        Label("Pensel", systemImage: "paintbrush.pointed").tag(SourceMaskTool.brush)
                        Label("Rektangel", systemImage: "rectangle").tag(SourceMaskTool.rectangle)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)

                    HStack(spacing: 6) {
                        maskColorButton(.exclude, color: .red, name: "Röd")
                        maskColorButton(.protect, color: .green, name: "Grön")
                        maskColorButton(
                            .controlPoints,
                            color: .orange,
                            name: "Orange"
                        )
                        maskColorButton(.erase, color: .white, name: "Sudda")
                    }

                    Button {
                        model.undoMask()
                    } label: {
                        Label("Ångra mask", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndoMask)
                    .keyboardShortcut("z", modifiers: .command)

                    Button {
                        model.invertSelectedMask()
                    } label: {
                        Label(
                            "Invertera mask",
                            systemImage: "circle.lefthalf.filled"
                        )
                    }
                    .disabled(
                        model.selectedSourceImage.map {
                            model.maskData(for: $0.id) == nil
                        } ?? true
                    )
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .help(
                        "Byt maskerade och omaskerade områden; åtgärden kan ångras"
                    )

                    Button(role: .destructive) {
                        model.clearSelectedMask()
                    } label: {
                        Label("Nollställ mask", systemImage: "trash")
                    }
                    .disabled(
                        model.selectedSourceImage.map {
                            model.maskData(for: $0.id) == nil
                        } ?? true
                    )
                    .help("Ta bort hela masken; åtgärden kan ångras")

                    Button(role: .destructive) {
                        model.removeSelectedSourceImage()
                    } label: {
                        Label("Ta bort källbild", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Ta bort bilden och dess kontrollpunkter")

                    if model.selectedSourceImage?.role == .fillOnly,
                       model.stitchedResultURL != nil {
                        Button {
                            model.showNadirRepairPreview()
                        } label: {
                            Label(
                                "Visa resultat",
                                systemImage: "checkmark.circle"
                            )
                        }
                        .disabled(model.phase != .ready)
                        .help(
                            "Blanda den maskerade nadirreparationen lokalt "
                                + "med Enblend och visa resultatet"
                        )
                    }
                }

                if model.isShowingNadirRepair {
                    if model.isAdjustingNadir {
                        Button {
                            model.toggleNadirAdjustment()
                        } label: {
                            Label("Förhandsvisning", systemImage: "checkmark.circle.fill")
                        }
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
                            Label("Justering", systemImage: "scope")
                        }
                    }
                    if model.isAdjustingNadir {
                        Button {
                            model.resetNadirAdjustment()
                        } label: {
                            Label(
                                "Återställ automatisk position",
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                        .disabled(model.displayedNadirAdjustment.isIdentity)
                    } else {
                        Button {
                            model.selectNadirRepairForMasking()
                        } label: {
                            Label(
                                model.hasNadirRepairMask
                                    ? "Redigera reparationsmask"
                                    : "Maskera reparation",
                                systemImage: "paintbrush.pointed"
                            )
                        }
                        .help(
                            "Välj vilka delar av nadirbilden som ska läggas "
                                + "över panoramat"
                        )
                        .disabled(model.phase != .ready)
                    }
                }

            }
        }
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: [.image, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importURLs(urls)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importURLs(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var repairAreaSymbol: String {
        switch model.selectedSourceImage?.direction {
        case .zenith: "arrow.up.circle"
        case .nadir: "arrow.down.circle"
        case .horizontal, nil: "scope"
        }
    }

    private func maskColorButton(
        _ intent: AppModel.SourceMaskIntent,
        color: Color,
        name: String
    ) -> some View {
        Button {
            model.sourceMaskIntent = intent
        } label: {
            Circle()
                .fill(color)
                .stroke(.primary.opacity(0.35), lineWidth: 1)
                .frame(width: 18, height: 18)
                .padding(5)
                .background(
                    model.sourceMaskIntent == intent
                        ? Color.accentColor.opacity(0.35)
                        : Color.clear,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .help(name)
    }

}

private struct SourceImagesView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Källbilder")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.isImporterPresented = true
                } label: {
                    Label("Lägg till bilder", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 180, maximum: 240),
                            spacing: 16
                        )
                    ],
                    spacing: 16
                ) {
                    ForEach(
                        Array(model.project.images.enumerated()),
                        id: \.element.id
                    ) { index, image in
                        Button {
                            model.selection = .source(image.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                SourceThumbnail(url: image.url)
                                    .aspectRatio(4 / 3, contentMode: .fit)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 8)
                                    )
                                HStack {
                                    Text("\(index + 1)")
                                        .font(
                                            .callout.monospacedDigit()
                                                .weight(.semibold)
                                        )
                                        .frame(width: 26, height: 26)
                                        .background(
                                            Color.secondary.opacity(0.14),
                                            in: Circle()
                                        )
                                    Text(image.filename)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                model.setRole(.alignment, for: image.id)
                            } label: {
                                Label(
                                    "Ingår i positionering",
                                    systemImage: image.role == .alignment
                                        ? "checkmark" : "scope"
                                )
                            }
                            Divider()
                            ForEach(
                                SourceImage.Direction.repairCases,
                                id: \.self
                            ) { direction in
                                Button {
                                    model.setRepairArea(direction, for: image.id)
                                } label: {
                                    Label(
                                        "\(direction.displayName) · Reparation",
                                        systemImage: image.role == .fillOnly
                                            && image.direction == direction
                                            ? "checkmark"
                                            : "square.2.layers.3d.bottom.filled"
                                    )
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}

private struct CreatePanoramaView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "panorama")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Skapa panorama")
                .font(.largeTitle.weight(.semibold))
            Text(
                "PanoWizard hittar kontrollpunkter, optimerar bilderna "
                    + "och sammanfogar panoramat automatiskt."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)

            Button {
                model.runWizard()
            } label: {
                Label("Skapa panorama", systemImage: "wand.and.stars")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canStitch)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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
                        + "reparationsbild väljer du även zenit eller nadir."
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
