import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false
    @State private var isStitchSettingsPresented = false

    var body: some View {
        NavigationSplitView {
            PanoramaSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
        } detail: {
            ZStack {
                PanoramaPreview(
                    panorama: model.panorama,
                    imageURL: model.selectedPreviewURL,
                    isStitched: model.isShowingStitchedPanorama,
                    nadirOverlayURL: model.isShowingNadirRepair
                        ? model.nadirOverlayURL
                        : nil,
                    selectedSource: model.selectedSourceImage,
                    maskData: model.selectedSourceImage.flatMap {
                        model.maskData(for: $0.id)
                    },
                    brushDiameter: model.brushDiameter,
                    zoom: model.sourceImageZoom,
                    isErasing: model.isErasingMask,
                    isAdjustingNadir: model.isAdjustingNadir,
                    nadirAdjustment: model.displayedNadirAdjustment,
                    onNadirAdjustmentChange: model.setNadirAdjustment,
                    onMaskChange: { data in
                        guard let image = model.selectedSourceImage else { return }
                        model.setMaskData(data, for: image.id)
                    }
                )
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
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.isImporterPresented = true
                } label: {
                    Label("Importera", systemImage: "plus")
                }

                Button {
                    model.stitch()
                } label: {
                    Label("Sammanfoga", systemImage: "wand.and.stars")
                }
                .disabled(!model.canStitch)

                Button {
                    isStitchSettingsPresented.toggle()
                } label: {
                    Label("Sammanfogningsinställningar", systemImage: "slider.horizontal.3")
                }
                .popover(isPresented: $isStitchSettingsPresented, arrowEdge: .bottom) {
                    StitchSettingsView(model: model)
                }

                if model.selectedSourceImage != nil {
                    Menu {
                        if let image = model.selectedSourceImage {
                            Picker("Riktning", selection: Binding(
                                get: { image.direction },
                                set: { direction in
                                    model.setDirection(direction, for: image.id)
                                }
                            )) {
                                ForEach(SourceImage.Direction.allCases, id: \.self) {
                                    Text($0.displayName).tag($0)
                                }
                            }
                            Divider()
                            Picker("Bildroll", selection: Binding(
                                get: { image.role },
                                set: { role in
                                    model.setRole(role, for: image.id)
                                }
                            )) {
                                Label(
                                    "Ingår i positionering",
                                    systemImage: "scope"
                                )
                                .tag(SourceImage.Role.alignment)
                                Label(
                                    "Reparation · påverkar inte geometrin",
                                    systemImage: "square.2.layers.3d.bottom.filled"
                                )
                                .tag(SourceImage.Role.fillOnly)
                            }
                        }
                    } label: {
                        Label(
                            "Bildegenskaper",
                            systemImage: model.selectedSourceImage?.role == .fillOnly
                                ? "paintbrush.pointed.fill"
                                : directionSymbol
                        )
                    }
                    .help("Ange bildens riktning och roll")

                    Button {
                        model.zoomSourceImageOut()
                    } label: {
                        Label("Zooma ut", systemImage: "minus.magnifyingglass")
                    }
                    .disabled(model.sourceImageZoom <= 1)
                    .keyboardShortcut("-", modifiers: .command)

                    Button {
                        model.zoomSourceImageIn()
                    } label: {
                        Label("Zooma in", systemImage: "plus.magnifyingglass")
                    }
                    .disabled(model.sourceImageZoom >= 8)
                    .keyboardShortcut("+", modifiers: .command)

                    Picker("Maskverktyg", selection: $model.isErasingMask) {
                        Label("Maskera", systemImage: "paintbrush")
                            .tag(false)
                        Label("Återställ", systemImage: "eraser")
                            .tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)

                    Slider(value: $model.brushDiameter, in: 8...240) {
                        Text("Penselstorlek")
                    }
                    .frame(width: 120)

                    Button {
                        model.undoMask()
                    } label: {
                        Label("Ångra mask", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndoMask)
                    .keyboardShortcut("z", modifiers: .command)

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
                    Button {
                        model.toggleNadirAdjustment()
                    } label: {
                        Label(
                            model.isAdjustingNadir ? "Klar" : "Justera nadir",
                            systemImage: model.isAdjustingNadir
                                ? "checkmark.circle.fill"
                                : "scope"
                        )
                    }
                    .help(
                        model.isAdjustingNadir
                            ? "Avsluta finjusteringen"
                            : "Finjustera nadirlagrets position"
                    )
                    .disabled(model.phase != .ready)

                    if model.isAdjustingNadir {
                        Button {
                            model.resetNadirAdjustment()
                        } label: {
                            Label(
                                "Återställ automatisk position",
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                        .disabled(model.nadirAdjustment.isIdentity)
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

                Button {
                } label: {
                    Label("Exportera", systemImage: "square.and.arrow.up")
                }
                .disabled(true)
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

    private var directionSymbol: String {
        switch model.selectedSourceImage?.direction {
        case .zenith: "arrow.up.circle"
        case .nadir: "arrow.down.circle"
        case .horizontal, nil: "scope"
        }
    }
}

private struct StitchSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Picker("Objektiv", selection: lensProfile) {
                ForEach(StitchingConfiguration.LensProfile.allCases, id: \.self) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }

            HStack {
                Text("Startsynfält")
                Spacer()
                TextField(
                    "Grader",
                    value: inputFieldOfView,
                    format: .number.precision(.fractionLength(0...1))
                )
                .frame(width: 64)
                Text("°")
                    .foregroundStyle(.secondary)
            }

            Text("Riktning och roll anges per bild i sidofältet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding(.vertical, 8)
    }

    private var lensProfile: Binding<StitchingConfiguration.LensProfile> {
        Binding(
            get: { model.project.stitching.lensProfile },
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

    private var inputFieldOfView: Binding<Double> {
        Binding(
            get: { model.project.stitching.inputHorizontalFieldOfView },
            set: { value in
                model.updateStitchingConfiguration {
                    $0.inputHorizontalFieldOfView = min(max(value, 20), 220)
                }
            }
        )
    }
}
