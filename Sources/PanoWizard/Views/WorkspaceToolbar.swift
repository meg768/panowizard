import SwiftUI

struct WorkspaceToolbarTheme {
    var pillHeight: CGFloat
    var horizontalPadding: CGFloat
    var restingFillOpacity: Double
    var hoverFillOpacity: Double
    var pressedFillOpacity: Double
    var restingBorderOpacity: Double
    var hoverBorderOpacity: Double
    var disabledOpacity: Double
    var hoverAnimation: Animation

    static let standard = WorkspaceToolbarTheme(
        pillHeight: 32,
        horizontalPadding: 11,
        restingFillOpacity: 0.075,
        hoverFillOpacity: 0.13,
        pressedFillOpacity: 0.18,
        restingBorderOpacity: 0.14,
        hoverBorderOpacity: 0.25,
        disabledOpacity: 0.48,
        hoverAnimation: .easeOut(duration: 0.12)
    )
}

private struct WorkspaceToolbarThemeKey: EnvironmentKey {
    static let defaultValue = WorkspaceToolbarTheme.standard
}

extension EnvironmentValues {
    var workspaceToolbarTheme: WorkspaceToolbarTheme {
        get { self[WorkspaceToolbarThemeKey.self] }
        set { self[WorkspaceToolbarThemeKey.self] = newValue }
    }
}

struct WorkspaceToolbarPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WorkspaceToolbarPillBody(configuration: configuration)
    }
}

struct WorkspaceToolbarMenuStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WorkspaceToolbarMenuBody(configuration: configuration)
    }
}

private struct WorkspaceToolbarMenuBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.workspaceToolbarTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .frame(width: theme.pillHeight, height: theme.pillHeight)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(fillOpacity), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(
                        Color.primary.opacity(borderOpacity),
                        lineWidth: 1
                    )
            }
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : theme.disabledOpacity)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .animation(theme.hoverAnimation, value: isHovering)
            .animation(theme.hoverAnimation, value: configuration.isPressed)
    }

    private var fillOpacity: Double {
        if configuration.isPressed {
            return theme.pressedFillOpacity
        }
        return isHovering && isEnabled
            ? theme.hoverFillOpacity
            : theme.restingFillOpacity
    }

    private var borderOpacity: Double {
        isHovering && isEnabled
            ? theme.hoverBorderOpacity
            : theme.restingBorderOpacity
    }
}

private struct WorkspaceToolbarPillBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.workspaceToolbarTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, theme.horizontalPadding)
            .frame(height: theme.pillHeight)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(fillOpacity), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        Color.primary.opacity(borderOpacity),
                        lineWidth: 1
                    )
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : theme.disabledOpacity)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .animation(theme.hoverAnimation, value: isHovering)
            .animation(theme.hoverAnimation, value: configuration.isPressed)
    }

    private var fillOpacity: Double {
        if configuration.isPressed {
            return theme.pressedFillOpacity
        }
        return isHovering && isEnabled
            ? theme.hoverFillOpacity
            : theme.restingFillOpacity
    }

    private var borderOpacity: Double {
        isHovering && isEnabled
            ? theme.hoverBorderOpacity
            : theme.restingBorderOpacity
    }
}
