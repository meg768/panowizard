import AppKit
import ImageIO
import SwiftUI

struct PanoramaSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            sourceToolbarRow

            ZStack {
                List {
                    Section {
                        if !model.project.images.isEmpty {
                            ForEach(
                                Array(model.project.images.enumerated()),
                                id: \.element.id
                            ) { index, image in
                                sourceImageRow(index: index, image: image)
                            }
                        }
                    }

                    if !model.project.images.isEmpty {
                        Section {
                            PanoramaNavigationRow(
                                title: "Inställningar",
                                systemImage: "slider.horizontal.3",
                                isSelected: model.selection == .settings
                            ) {
                                model.selection = .settings
                            }
                            PanoramaNavigationRow(
                                title: "Förhandsvisa",
                                systemImage: "eye",
                                isSelected: model.selection == .panorama
                            ) {
                                model.selection = .panorama
                            }
                            PanoramaNavigationRow(
                                title: "Retuschering",
                                systemImage: "paintbrush.pointed",
                                isSelected: model.selection == .retouch
                            ) {
                                model.selection = .retouch
                            }
                            PanoramaNavigationRow(
                                title: "Exportera",
                                systemImage: "square.and.arrow.up",
                                isSelected: model.selection == .export
                            ) {
                                model.selection = .export
                            }
                        } header: {
                            SidebarSectionHeader("Panorama")
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
        .onDeleteCommand {
            model.removeSelectedSourceImage()
        }
    }

    private var sourceToolbarRow: some View {
        HStack(spacing: 12) {
            Text("Källbilder")
                .font(.headline)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func sourceImageRow(
        index: Int,
        image: SourceImage
    ) -> some View {
        SourceImageRow(
            index: index,
            image: image,
            hasMask: model.maskDataByImageID[image.id] != nil
                || model.protectedMaskDataByImageID[image.id] != nil,
            onSelect: { asRightImage in
                model.selectSourceImage(
                    image.id,
                    asRightImage: asRightImage
                )
            },
            onSetRole: {
                model.setRole($0, for: image.id)
            },
            onToggleEnabled: {
                model.toggleSourceImageEnabled(image.id)
            },
            onDelete: {
                model.removeSourceImage(image.id)
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

}

private struct SidebarSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
            Spacer(minLength: 12)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private extension SidebarSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

private struct PanoramaNavigationRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.24) : Color.clear
        )
    }
}

private struct SourceImageRow: View {
    let index: Int
    let image: SourceImage
    let hasMask: Bool
    let onSelect: (Bool) -> Void
    let onSetRole: (SourceImage.Role) -> Void
    let onToggleEnabled: () -> Void
    let onDelete: () -> Void

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
                    .help(image.filename)
                HStack(spacing: 4) {
                    Text(roleDescription)
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

            Spacer(minLength: 16)

            SourceImageSettingsButton(
                role: image.role,
                onSetAutomatic: {
                    onSelect(false)
                    onSetRole(.automatic)
                },
                onSetAlignment: {
                    onSelect(false)
                    onSetRole(.alignment)
                },
                onSetRepair: {
                    onSelect(false)
                    onSetRole(.fillOnly)
                },
                onDelete: onDelete
            )
            .frame(width: 32, height: 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(NSEvent.modifierFlags.contains(.shift))
        }
        .contextMenu {
            sourceImageRoleMenu
        }
    }

    @ViewBuilder
    private var sourceImageRoleMenu: some View {
        Button {
            onSelect(false)
            onSetRole(.automatic)
        } label: {
            Label(
                "Automatisk positionering",
                systemImage: image.role == .automatic
                    ? "checkmark" : "wand.and.stars"
            )
        }
        Button {
            onSelect(false)
            onSetRole(.alignment)
        } label: {
            Label(
                "Ingår i positionering",
                systemImage: image.role == .alignment ? "checkmark" : "scope"
            )
        }
        Divider()
        Button {
            onSelect(false)
            onSetRole(.fillOnly)
        } label: {
            Label(
                "Reparation",
                systemImage: image.role == .fillOnly
                    ? "checkmark"
                    : "square.2.layers.3d.bottom.filled"
            )
        }
        Divider()
        Button("Ta bort bild…", role: .destructive, action: onDelete)
    }

    private var roleDescription: String {
        guard image.role == .automatic else { return image.role.displayName }
        return image.effectiveRole == .fillOnly
            ? "Automatisk · Reparation"
            : image.role.displayName
    }
}

private struct SourceImageSettingsButton: NSViewRepresentable {
    let role: SourceImage.Role
    let onSetAutomatic: () -> Void
    let onSetAlignment: () -> Void
    let onSetRepair: () -> Void
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HoverPopUpButton {
        let button = HoverPopUpButton(frame: .zero, pullsDown: true)
        button.target = context.coordinator
        button.action = #selector(Coordinator.chooseRole(_:))
        button.usesItemFromMenu = true
        button.autoenablesItems = false
        button.preferredEdge = .minY
        button.bezelStyle = .circular
        button.isBordered = false
        button.controlSize = .regular
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Bildinställningar"
        button.setAccessibilityLabel("Bildinställningar")
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow

        let menu = NSMenu()
        let buttonFace = NSMenuItem(
            title: "",
            action: nil,
            keyEquivalent: ""
        )
        buttonFace.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: "Bildinställningar"
        )
        buttonFace.tag = Coordinator.buttonFaceTag
        menu.addItem(buttonFace)

        let automatic = NSMenuItem(
            title: "Automatisk positionering",
            action: nil,
            keyEquivalent: ""
        )
        automatic.tag = Coordinator.automaticTag
        menu.addItem(automatic)

        let alignment = NSMenuItem(
            title: "Ingår i positionering",
            action: nil,
            keyEquivalent: ""
        )
        alignment.tag = Coordinator.alignmentTag
        menu.addItem(alignment)
        menu.addItem(.separator())

        let repair = NSMenuItem(
            title: "Reparation",
            action: nil,
            keyEquivalent: ""
        )
        repair.tag = Coordinator.repairTag
        menu.addItem(repair)
        menu.addItem(.separator())

        let delete = NSMenuItem(
            title: "Ta bort bild…",
            action: nil,
            keyEquivalent: ""
        )
        delete.tag = Coordinator.deleteTag
        menu.addItem(delete)
        button.menu = menu
        button.selectItem(at: 0)
        button.synchronizeTitleAndSelectedItem()
        updateMenu(in: button)
        return button
    }

    func updateNSView(_ button: HoverPopUpButton, context: Context) {
        context.coordinator.parent = self
        updateMenu(in: button)
    }

    private func updateMenu(in button: NSPopUpButton) {
        button.itemArray.first { $0.tag == Coordinator.automaticTag }?.state =
            role == .automatic
                ? NSControl.StateValue.on : NSControl.StateValue.off
        button.itemArray.first { $0.tag == Coordinator.alignmentTag }?.state =
            role == .alignment
            ? NSControl.StateValue.on : NSControl.StateValue.off
        button.itemArray.first { $0.tag == Coordinator.repairTag }?.state =
            role == .fillOnly
                ? NSControl.StateValue.on : NSControl.StateValue.off
    }

    @MainActor
    final class Coordinator: NSObject {
        static let buttonFaceTag = 100
        static let automaticTag = 101
        static let alignmentTag = 102
        static let repairTag = 103
        static let deleteTag = 104

        var parent: SourceImageSettingsButton

        init(parent: SourceImageSettingsButton) {
            self.parent = parent
        }

        @objc func chooseRole(_ sender: NSPopUpButton) {
            switch sender.selectedTag() {
            case Self.automaticTag:
                parent.onSetAutomatic()
            case Self.alignmentTag:
                parent.onSetAlignment()
            case Self.repairTag:
                parent.onSetRepair()
            case Self.deleteTag:
                parent.onDelete()
            default:
                break
            }
        }
    }
}

private final class HoverPopUpButton: NSPopUpButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        wantsLayer = true
        contentTintColor = isHovered ? .white : .labelColor
        layer?.backgroundColor = (
            isHovered ? NSColor.controlAccentColor : NSColor.controlColor
        ).cgColor
        layer?.borderColor = (
            isHovered ? NSColor.controlAccentColor : NSColor.separatorColor
        ).cgColor
        layer?.borderWidth = isHovered ? 2 : 1
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isHovered ? 0.22 : 0
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        needsDisplay = true
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
