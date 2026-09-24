import SwiftUI

struct PanoramaSidebar: View {
    @Bindable var model: AppModel
    @State private var pendingDeletion: SourceImage?
    @State private var deletionError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Images").font(.headline)
                Spacer(minLength: 12)
                Button {
                    model.isImporterPresented = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(WorkspaceToolbarPillStyle())
                .help("Add source images")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.bar)

            ZStack {
                List(selection: $model.selection) {
                    Section {
                        ForEach(
                            Array(model.project.images.enumerated()),
                            id: \.element.id
                        ) { index, image in
                            sourceRow(index: index, image: image)
                        }
                    }

                    if !model.project.images.isEmpty {
                        Section {
                            navigationRow(
                                "Preview",
                                systemImage: "eye",
                                selection: .panorama
                            )
                            navigationRow(
                                "Retouch",
                                systemImage: "paintbrush.pointed",
                                selection: .retouch
                            )
                            navigationRow(
                                "Export",
                                systemImage: "square.and.arrow.up",
                                selection: .export
                            )
                        } header: {
                            HStack(spacing: 12) {
                                Text("Panorama")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 12)
                                Button {
                                    model.stitch()
                                } label: {
                                    Label("Create", systemImage: "pano")
                                }
                                .buttonStyle(WorkspaceToolbarPillStyle())
                                .disabled(!model.canStitch)
                                .help("Create a panorama with the current images and masks")
                            }
                            .textCase(nil)
                            .padding(.leading, 4)
                            .padding(.trailing, 20)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.top, 8, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))

                if model.project.images.isEmpty {
                    ContentUnavailableView(
                        "No Images",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Drag in images to get started.")
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .onDeleteCommand {
            pendingDeletion = model.selectedSourceImage
        }
        .confirmationDialog(
            "Remove Source Image?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { image in
            Button("Remove from Project", role: .destructive) {
                model.removeSourceImage(image.id)
            }
            Button("Move Source File to Trash", role: .destructive) {
                do {
                    try model.moveSourceImageToTrash(image.id)
                } catch {
                    deletionError = "\(image.filename) could not be moved to "
                        + "the Trash: \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { image in
            Text(
                "\(image.filename) can be removed from the project or moved "
                    + "to the Trash."
            )
        }
        .alert("Could Not Remove Source File", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "Unknown error")
        }
    }

    private func sourceRow(index: Int, image: SourceImage) -> some View {
        return HStack(spacing: 10) {
                Button {
                    model.selectAndToggleSourceImageEnabled(image.id)
                } label: {
                    Text("\(index + 1)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(image.isEnabled ? .white : .secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            image.isEnabled
                                ? Color.accentColor
                                : Color.secondary.opacity(0.16),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(image.isEnabled ? "Disable image" : "Enable image")

                SourceThumbnail(image: image)
                    .frame(width: 52, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(image.filename)
                        .lineLimit(1)
                        .help(image.filename)
                    HStack(spacing: 4) {
                        Text(
                            "\(image.orientedPixelWidth) × "
                                + "\(image.orientedPixelHeight)"
                        )
                        if model.maskDataByImageID[image.id] != nil
                            || model.protectedMaskDataByImageID[image.id] != nil {
                            Image(systemName: "rectangle.inset.filled")
                                .foregroundStyle(.red)
                                .help("The image has an individual mask")
                        }
                        if image.effectiveRole == .fillOnly {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundStyle(.orange)
                                .help("Repair image — does not affect panorama-ring geometry")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .tag(ProjectSelection.source(image.id))
        .contextMenu {
            Menu("Image Type") {
                roleButton("Automatic", role: .automatic, image: image)
                roleButton("Panorama Ring", role: .alignment, image: image)
                roleButton("Repair Image", role: .fillOnly, image: image)
            }
            Button("Remove Image…", role: .destructive) {
                model.selectSourceImage(image.id)
                pendingDeletion = image
            }
        }
    }

    @ViewBuilder
    private func roleButton(
        _ title: String,
        role: SourceImage.Role,
        image: SourceImage
    ) -> some View {
        Button {
            model.setSourceImageRole(image.id, role: role)
        } label: {
            if image.role == role {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func navigationRow(
        _ title: String,
        systemImage: String,
        selection: ProjectSelection
    ) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        .padding(.vertical, 5)
        .tag(selection)
    }
}

struct SourceThumbnail: View {
    let image: SourceImage

    var body: some View {
        if let thumbnail = SourceImageRaster.load(
            image,
            maximumPixelSize: 240
        ) {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Color.secondary.opacity(0.15)
                .overlay {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
        }
    }

}
