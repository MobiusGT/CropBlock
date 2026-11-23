import SwiftUI

/// High-contrast matched pill ButtonStyle for the paired "Deep Scan All" and "Crop All" toolbar actions.
/// Preserves native keyboard focus, VoiceOver semantics, hover/press feedback, and crisp contrast in
/// Light mode, Dark mode, Increase Contrast, macOS 15 Sequoia, and macOS 26 Liquid Glass.
struct ToolbarBatchButtonStyle: ButtonStyle {
    enum Role {
        case primaryAccent
        case secondaryContrast
    }

    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        ToolbarBatchPill(configuration: configuration, role: role)
    }
}

private struct ToolbarBatchPill: View {
    let configuration: ButtonStyle.Configuration
    let role: ToolbarBatchButtonStyle.Role

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(foreground)
            .padding(.horizontal, Space.md)
            .frame(height: 28)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
            .opacity(effectiveOpacity)
            .contentShape(Capsule())
            .onHover { hovering in
                withAnimation(Motion.quick(reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
    }

    private var foreground: Color {
        switch role {
        case .primaryAccent: Palette.onAccent
        case .secondaryContrast: Surface.toolbarSecondaryForeground
        }
    }

    private var background: Color {
        switch role {
        case .primaryAccent:
            if configuration.isPressed {
                return Palette.accent.opacity(0.82)
            }
            return isHovered ? Palette.accent.opacity(0.92) : Palette.accent
        case .secondaryContrast:
            if configuration.isPressed {
                return Surface.toolbarSecondaryHover.opacity(0.86)
            }
            return isHovered ? Surface.toolbarSecondaryHover : Surface.toolbarSecondaryFill
        }
    }

    private var borderColor: Color {
        switch role {
        case .primaryAccent:
            return Color.primary.opacity(0.14)
        case .secondaryContrast:
            return Surface.toolbarSecondaryBorder
        }
    }

    private var effectiveOpacity: Double {
        isEnabled ? 1.0 : 0.42
    }
}
