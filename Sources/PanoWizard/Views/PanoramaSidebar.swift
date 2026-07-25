import ImageIO
import SwiftUI

struct PanoramaSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            if !model.project.images.isEmpty {
                Section("Panorama") {
                    PanoramaResultRow(
                        isReady: model.stitchedResultURL != nil,
                        hasNadirRepair: model.nadirOverlayURL != nil,
                        hasNadirMask: model.hasNadirRepairMask
                    )
                        .tag(ProjectSelection.panorama)
                        .disabled(model.stitchedResultURL == nil)
                }

                Section("Källbilder") {
                    ForEach(Array(model.project.images.enumerated()), id: \.element.id) {
                        index,
                        image in
                        SourceImageRow(
                            index: index,
                            image: image,
                            hasMask: model.maskData(for: image.id) != nil,
                            onSetRole: { role in
                                model.setRole(role, for: image.id)
                            },
                            onSetDirection: { direction in
                                model.setDirection(direction, for: image.id)
                            }
                        )
                            .tag(ProjectSelection.source(image.id))
                    }
                }
            }
        }
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

private struct PanoramaResultRow: View {
    let isReady: Bool
    let hasNadirRepair: Bool
    let hasNadirMask: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sammanfogat panorama")
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: isReady ? "panorama.fill" : "panorama")
                .font(.title3)
                .foregroundStyle(isReady ? Color.accentColor : .secondary)
                .frame(width: 44)
        }
        .padding(.vertical, 3)
    }

    private var status: String {
        if hasNadirRepair {
            return hasNadirMask
                ? "Nadir placerad och maskerad"
                : "Nadir placerad · mask saknas"
        }
        return isReady ? "Klar för förhandsvisning" : "Inte sammanfogat"
    }
}

private struct SourceImageRow: View {
    let index: Int
    let image: SourceImage
    let hasMask: Bool
    let onSetRole: (SourceImage.Role) -> Void
    let onSetDirection: (SourceImage.Direction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            SourceThumbnail(url: image.url)
                .frame(width: 52, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(image.filename)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("Bild \(index + 1) · \(image.direction.displayName)")
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
