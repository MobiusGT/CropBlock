import SwiftUI

/// Settings > Appearance: the accent color. Light and dark mode follow macOS.
struct AppearanceSettings: View {
    @Bindable private var store = ThemeStore.shared

    var body: some View {
        Section {
            AccentPreview()
                .padding(.vertical, Space.xs)
            LabeledContent("Accent color") {
                VStack(alignment: .trailing, spacing: Space.xs) {
                    HStack(spacing: Space.sm) {
                        ForEach(Theme.all) { theme in
                            AccentSwatch(theme: theme, selected: store.themeID == theme.id) {
                                store.themeID = theme.id
                            }
                        }
                    }
                    Text(store.theme.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AccentPreview: View {
    private let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(height: 152)
        .background(.background, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the accent color")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.quaternary).frame(width: Space.sm, height: Space.sm)
                }
            }
            .padding(.leading, Space.xs)
            .padding(.bottom, Space.sm)
            sidebarRow("Dune.mkv", symbol: "crop", selected: true)
            sidebarRow("Arrival.mkv", symbol: "checkmark.seal.fill", selected: false)
            sidebarRow("Tenet.mkv", symbol: "exclamationmark.triangle.fill", selected: false)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .frame(width: 140)
        .background(.background.secondary)
    }

    private func sidebarRow(_ title: String, symbol: String, selected: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout)
            .lineLimit(1)
            .foregroundStyle(selected ? Palette.onAccent : .primary)
            .padding(.horizontal, Space.sm)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(
                selected ? Palette.accent : .clear,
                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dune.mkv").font(.headline)
                Spacer()
                Text("2.39:1").font(.caption).monospacedDigit().foregroundStyle(Palette.accentText)
            }
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Surface.previewCanvas)
                .frame(height: 60)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .strokeBorder(Palette.accent, lineWidth: 2)
                        .padding(.vertical, Space.md)
                        .padding(.horizontal, Space.xs)
                }
            Spacer(minLength: 0)
            HStack {
                Text("T 140 · B 140")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Apply Crop", systemImage: "crop")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Space.md)
                    .frame(height: 24)
                    .background(Palette.accent, in: Capsule())
            }
        }
        .padding(Space.md)
    }
}

private struct AccentSwatch: View {
    let theme: Theme
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Circle()
                .fill(fill)
                .frame(width: Space.lg, height: Space.lg)
                .overlay {
                    if selected {
                        Circle().fill(theme.onAccent).frame(width: 6, height: 6) // grid: ok swatch indicator dot
                    }
                }
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.name)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: AnyShapeStyle {
        if let tint = theme.tint {
            AnyShapeStyle(tint)
        } else {
            AnyShapeStyle(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                    center: .center
                )
            )
        }
    }
}
