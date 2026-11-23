import SwiftUI

/// Bridges macOS 26 Liquid Glass APIs with clean native macOS 15 Sequoia fallbacks.
extension View {
    /// Floating control capsule (e.g., preview sample switcher or overlay toggle).
    @ViewBuilder
    func floatingControlCapsule() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Surface.hairline, lineWidth: 1))
        }
    }

    /// Floating non-interactive badge pill over controls or chrome.
    @ViewBuilder
    func floatingGlassPill() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Surface.hairline, lineWidth: 1))
        }
    }
}

/// Toolbar spacer compatible with both macOS 26 (Liquid Glass grouping) and macOS 15.
struct CompatToolbarFlexibleSpacer: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
        }
    }
}

struct CompatToolbarFixedSpacer: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Color.clear.frame(width: Space.xs, height: Space.xs)
            }
        }
    }
}

extension ToolbarContent {
    /// Removes the default Liquid Glass backdrop behind high-contrast custom toolbar pills on macOS 26+
    /// so solid capsules keep crisp contrast without glass-on-glass washout.
    @ToolbarContentBuilder
    func compatSharedBackgroundHidden() -> some ToolbarContent {
        if #available(macOS 26, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
