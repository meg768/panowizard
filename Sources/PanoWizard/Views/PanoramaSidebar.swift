import AppKit
import ImageIO
import SwiftUI

struct PanoramaSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List {
            if !model.project.images.isEmpty {
                Section {
                    ForEach(
                        Array(model.project.images.enumerated()),
                        id: \.element.id
                    ) { index, image in
                        SourceImageRow(
                            index: index,
                            image: image,
                            hasMask: model.maskData(for: image.id) != nil,
                            onSelect: { asRightImage in
                                model.selectSourceImage(
                                    image.id,
                                    asRightImage: asRightImage
                                )
                            },
                            onSetRole: {
                                model.setRole($0, for: image.id)
                            },
                            onSetDirection: {
                                model.setDirection($0, for: image.id)
                            }
                        )
                        .listRowBackground(
                            model.mainSourceImageID == image.id
                                ? Color.accentColor.opacity(0.24)
                                : model.rightSourceImageID == image.id
                                    ? Color.orange.opacity(0.22)
                                    : Color.clear
                        )
                    }
                } header: {
                    SidebarTitle("Källbilder")
                }

                Section {
                    Button {
                        model.selection = .settings
                    } label: {
                        PanoramaSettingsRow()
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        model.selection == .settings
                            ? Color.accentColor.opacity(0.24)
                            : Color.clear
                    )

                    Button {
                        model.selection = .panorama
                    } label: {
                        PanoramaPreviewRow()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.stitchedResultURL == nil)
                    .listRowBackground(
                        model.selection == .panorama
                            ? Color.accentColor.opacity(0.24)
                            : Color.clear
                    )

                    Button {
                        model.selection = .export
                    } label: {
                        PanoramaExportRow()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.stitchedResultURL == nil)
                    .listRowBackground(
                        model.selection == .export
                            ? Color.accentColor.opacity(0.24)
                            : Color.clear
                    )
                } header: {
                    SidebarTitle("Panorama")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .overlay {
            if model.project.images.isEmpty {
                ContentUnavailableView(
                    "Inga bilder",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Dra in bilder för att börja.")
                )
            }
        }
        .navigationTitle(model.project.title)
        .onDeleteCommand {
            model.removeSelectedSourceImage()
        }
    }

}

private struct SidebarTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

private struct PanoramaSettingsRow: View {
    var body: some View {
        Label {
            Text("Inställningar")
        } icon: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PanoramaPreviewRow: View {
    var body: some View {
        Label {
            Text("Förhandsvisning")
        } icon: {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PanoramaExportRow: View {
    var body: some View {
        Label {
            Text("Exportera")
        } icon: {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SourceImageRow: View {
    let index: Int
    let image: SourceImage
    let hasMask: Bool
    let onSelect: (Bool) -> Void
    let onSetRole: (SourceImage.Role) -> Void
    let onSetDirection: (SourceImage.Direction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.14), in: Circle())

            SourceThumbnail(url: image.url)
                .frame(width: 52, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(image.filename)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(image.direction.displayName)
                    if image.role == .fillOnly {
                        Text("· Reparation")
                    }
                    if hasMask {
                        Label("Maskerad", systemImage: "paintbrush.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                            .help("Bilden har en exkluderingsmask")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(NSEvent.modifierFlags.contains(.shift))
        }
        .help(image.filename)
        .contextMenu {
            Picker("Riktning", selection: Binding(
                get: { image.direction },
                set: { direction in onSetDirection(direction) }
            )) {
                ForEach(SourceImage.Direction.allCases, id: \.self) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }
            Divider()
            Picker("Bildroll", selection: Binding(
                get: { image.role },
                set: { role in onSetRole(role) }
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
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
