import AppKit
import SwiftUI

/// Adaptive semantic surfaces and status colors (4-variant light/dark/high-contrast).
enum Surface {
    /// Subtle translucent neutral card surface that picks up the desktop tint.
    static let card = Color(
        nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]) {
            case .darkAqua: NSColor.white.withAlphaComponent(0.05)
            case .accessibilityHighContrastDarkAqua: NSColor.white.withAlphaComponent(0.10)
            case .accessibilityHighContrastAqua: NSColor.black.withAlphaComponent(0.05)
            default: NSColor.black.withAlphaComponent(0.03)
            }
        }
    )

    static let hairline = Color(
        nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]) {
            case .darkAqua: NSColor.white.withAlphaComponent(0.12)
            case .accessibilityHighContrastDarkAqua: NSColor.white.withAlphaComponent(0.32)
            case .accessibilityHighContrastAqua: NSColor.black.withAlphaComponent(0.28)
            default: NSColor.black.withAlphaComponent(0.10)
            }
        }
    )

    /// Video preview canvas backdrop stays dark in both light and dark mode so black bars read clearly.
    static let previewCanvas = Color(light: 0x111216, dark: 0x0B0C10, highContrastLight: 0x090A0D, highContrastDark: 0x050608)
    /// Dimmed overlay over cropped-out bars.
    static let cropScrim = Color.black.opacity(0.68)
    /// Dark capsule scrim behind HUD text drawn over video frames.
    static let hudPill = Color.black.opacity(0.76)
    static let hudForeground = Color.white

    /// Semantic status colors — ALWAYS paired with an SF Symbol and text label.
    static let success = Color(light: 0x157F3D, dark: 0x4ADE80, highContrastLight: 0x0F5D2B, highContrastDark: 0x86EFAC)
    static let warning = Color(light: 0xB45309, dark: 0xFBBF24, highContrastLight: 0x8C3D06, highContrastDark: 0xFDE68A)
    static let danger = Color(light: 0xC81E1E, dark: 0xF87171, highContrastLight: 0x9B1C1C, highContrastDark: 0xFCA5A5)

    static let warningTint = Color(
        nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]) {
            case .darkAqua, .accessibilityHighContrastDarkAqua:
                NSColor(hex: 0xF59E0B).withAlphaComponent(0.16)
            default:
                NSColor(hex: 0xF59E0B).withAlphaComponent(0.12)
            }
        }
    )

    static let dangerTint = Color(
        nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]) {
            case .darkAqua, .accessibilityHighContrastDarkAqua:
                NSColor(hex: 0xEF4444).withAlphaComponent(0.16)
            default:
                NSColor(hex: 0xEF4444).withAlphaComponent(0.10)
            }
        }
    )

    /// High-contrast secondary toolbar action pill (paired beside accented "Crop All").
    static let toolbarSecondaryFill = Color(
        light: 0x262A35,
        dark: 0x3A3F4E,
        highContrastLight: 0x151820,
        highContrastDark: 0x4A5064
    )
    static let toolbarSecondaryHover = Color(
        light: 0x343948,
        dark: 0x474D5F,
        highContrastLight: 0x242834,
        highContrastDark: 0x5A6178
    )
    static let toolbarSecondaryForeground = Color.white
    static let toolbarSecondaryBorder = Color(
        nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]) {
            case .darkAqua: NSColor.white.withAlphaComponent(0.22)
            case .accessibilityHighContrastDarkAqua: NSColor.white.withAlphaComponent(0.45)
            case .accessibilityHighContrastAqua: NSColor.black.withAlphaComponent(0.45)
            default: NSColor.black.withAlphaComponent(0.20)
            }
        }
    )
}
