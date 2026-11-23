# Crop Block Design System

Every view in `Sources/CropBlock/` uses tokens from `Sources/CropBlock/UI/`. Never write raw hex colors, raw corner radii, raw spacing off the 4 pt grid, or raw animation durations in views.

## Theme (`UI/Theme.swift`)
- `ThemeStore.defaultID` stays `"system"`.
- `ThemeStore.brand` is Slate Indigo (`light: 0xA5ADFF, base: 0x5E6AD2, deep: 0x4650B8`), active only while macOS is set to Multicolor.
- Use `.tint` or `Palette.accent` for interactive accents, `Palette.accentText` for accent-colored labels, and `Palette.onAccent` for text/icons drawn over accent fills.

## Spacing & Alignment (`UI/Grid.swift`)
- Use `Space`: `xs` (4), `sm` (8), `md` (12), `lg` (16), `xl` (20), `xxl` (24), `section` (32), `margin` (20).
- Window margins are `Space.margin` (20); cards pad `Space.lg` (16); related controls sit `Space.sm` (8) apart; groups sit `Space.xl` (20) apart.
- Align tables with `Grid`/`GridRow` and `.monospacedDigit()`; align labels with `LabeledContent` or grouped `Form`.
- Mark custom panes and cards with `.gridArea` and `.gridProbe` so `tools/check-layout.swift` verifies edges.

## Surfaces & Status (`UI/Surfaces.swift`)
- Neutral surfaces use system semantics (`.background`, `.controlBackgroundColor`, `.separator`) or `Surface.card` / `Surface.subtle` / `Surface.hairline` (all 4-variant light/dark/high-contrast colors).
- Preview scrims (`Surface.previewCanvas`, `Surface.cropScrim`, `Surface.hudPill`) stay dark in both appearances so video frames and floating dimension text keep >= 4.5:1 contrast.
- Status colors (`Surface.success`, `Surface.warning`, `Surface.danger`) ALWAYS pair with an SF Symbol and text label.

## Radii (`UI/Radius.swift`)
- `xs` (4) inline tags/badges, `sm` (8) controls & rows, `md` (12) cards & preview frame, `lg` (16) drop zones & banners.
- Inner corners stay concentric: `inner = outer - inset`.

## Motion (`UI/Motion.swift`)
- All view transitions and state animations route through `Motion.quick`, `Motion.ui`, or `Motion.select`, returning `nil` under Reduce Motion.
- Never animate a view's first layout or units (`px`, `:1`). Use `.contentTransition(.numericText())` on changing numbers only.

## Compatibility (`UI/Compat.swift`)
- Guard macOS 26 Liquid Glass (`.glassEffect`, `ToolbarSpacer`) with `#available(macOS 26, *)` and provide clean `.regularMaterial` / standard toolbar fallbacks for macOS 15.
- Liquid Glass applies only to floating controls and chrome, never to content cards or rows.
