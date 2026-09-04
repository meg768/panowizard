import ImageIO
import SwiftUI

struct PanoramaSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Källbilder").font(.headline)
                Spacer(minLength: 12)
                Button {
                    model.isImporterPresented = true
                } label: {
                    Label("Lägg till", systemImage: "plus")
                }
                .buttonStyle(WorkspaceToolbarPillStyle())
                .help("Lägg till källbilder")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.bar)

            ZStack {
                List {
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
                                "Förhandsvisa",
                                systemImage: "eye",
                                selection: .panorama
                            )
                            navigationRow(
                                "Retuschering",
                                systemImage: "paintbrush.pointed",
                                selection: .retouch
                            )
                            navigationRow(
                                "Exportera",
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
                                    Label("Skapa", systemImage: "pano")
                                }
                                .buttonStyle(WorkspaceToolbarPillStyle())
                                .disabled(!model.canStitch)
                                .help("Skapa panorama med aktuella bilder och masker")
                            }
                            .textCase(nil)
                            .padding(.horizontal, 4)
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
                        "Inga bilder",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Dra in bilder för att börja.")
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .onDeleteCommand { model.removeSelectedSourceImage() }
    }

    private func sourceRow(index: Int, image: SourceImage) -> some View {
        HStack(spacing: 10) {
                Button {
                    model.toggleSourceImageEnabled(image.id)
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
                .help(image.isEnabled ? "Inaktivera bilden" : "Aktivera bilden")

                SourceThumbnail(url: image.url)
                    .frame(width: 52, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(image.filename).lineLimit(1).help(image.filename)
                    HStack(spacing: 4) {
                        Text("\(image.pixelWidth) × \(image.pixelHeight)")
                        if model.maskDataByImageID[image.id] != nil
                            || model.protectedMaskDataByImageID[image.id] != nil {
                            Image(systemName: "paintbrush.fill")
                                .foregroundStyle(.red)
                                .help("Bilden har en individuell mask")
                        }
                        if image.effectiveRole == .fillOnly {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundStyle(.orange)
                                .help("Reparationsbild – påverkar inte panoramaringens geometri")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                Button(role: .destructive) {
                    model.removeSourceImage(image.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Ta bort bild")
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectSourceImage(image.id) }
        .padding(.vertical, 4)
        .listRowBackground(
            model.selectedSourceImage?.id == image.id
                ? Color.accentColor.opacity(0.24)
                : Color.clear
        )
        .contextMenu {
            Menu("Bildtyp") {
                roleButton("Automatisk", role: .automatic, image: image)
                roleButton("Panoramaring", role: .alignment, image: image)
                roleButton("Reparationsbild", role: .fillOnly, image: image)
            }
            Button("Ta bort bild…", role: .destructive) {
                model.removeSourceImage(image.id)
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
        Button {
            model.selection = selection
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .listRowBackground(
            model.selection == selection
                ? Color.accentColor.opacity(0.24)
                : Color.clear
        )
    }
}

struct SourceThumbnail: View {
    let url: URL

    var body: some View {
        if let image = Self.thumbnail(at: url) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Color.secondary.opacity(0.15)
                .overlay {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
        }
    }

    private static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240
            ] as CFDictionary
        )
    }
}
