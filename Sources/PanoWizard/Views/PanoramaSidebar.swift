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
                            hasMask: model.maskDataByImageID[image.id] != nil
                                || model.protectedMaskDataByImageID[image.id] != nil
                                || model.controlPointMaskDataByImageID[image.id] != nil,
                            onSelect: { asRightImage in
                                model.selectSourceImage(
                                    image.id,
                                    asRightImage: asRightImage
                                )
                            },
                            onSetRole: {
                                model.setRole($0, for: image.id)
                            },
                            onSetRepairArea: {
                                model.setRepairArea($0, for: image.id)
                            },
                            onToggleEnabled: {
                                model.toggleSourceImageEnabled(image.id)
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

            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.top, 8, for: .scrollContent)
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

private struct SourceImageRow: View {
    let index: Int
    let image: SourceImage
    let hasMask: Bool
    let onSelect: (Bool) -> Void
    let onSetRole: (SourceImage.Role) -> Void
    let onSetRepairArea: (SourceImage.Direction) -> Void
    let onToggleEnabled: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleEnabled) {
                Text("\(index + 1)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(
                        image.isEnabled ? Color.white : Color.secondary
                    )
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
                Text(image.filename)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(image.role == .alignment
                        ? image.role.displayName
                        : "\(image.direction.displayName) · Reparation")
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
            sourceImageRoleMenu
        }
    }

    @ViewBuilder
    private var sourceImageRoleMenu: some View {
        Button {
            onSetRole(.alignment)
        } label: {
            Label(
                "Ingår i positionering",
                systemImage: image.role == .alignment ? "checkmark" : "scope"
            )
        }
        Divider()
        ForEach(SourceImage.Direction.repairCases, id: \.self) { direction in
            Button {
                onSetRepairArea(direction)
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
