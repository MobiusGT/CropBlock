# Crop Block (`CropBlock`)

A lightweight, native macOS SwiftUI app (macOS 15+ with conditional macOS 26 Liquid Glass) that detects black letterbox/pillarbox bars in MKV files using `ffprobe`/`ffmpeg` (`cropdetect`) and losslessly removes them in-place with `mkvpropedit`.

- Repository: https://github.com/MobiusGT/CropBlock
- Bundle ID: `io.github.mobiusgt.cropblock`

## Layout

- `Sources/CropBlock/` — SwiftUI macOS app (`@MainActor` default isolation).
- `Sources/CropBlockKit/` — Pure Swift logic, crop/SAR math, EBML Matroska header reader, `ToolResolver`, `ProcessRunner`, `CropBackend`, and `ReceiptStore` (zero SwiftUI imports).
- `Tests/CropBlockKitTests/` — Swift Testing unit and integration tests.
- `Package.swift` — SwiftPM package (`.macOS(.v15)`). No Xcode project.
- `build.sh` — Builds, signs, and installs `~/Applications/CropBlock.app`.
- `Icon/AppIcon.icon` — Icon Composer app icon (JSON + SVG layers).
- `docs/` — [BRIEF.md](docs/BRIEF.md), [DESIGN.md](docs/DESIGN.md), [GLOSSARY.md](docs/GLOSSARY.md), [STORIES.md](docs/STORIES.md).

## Build and Check

- Build and install: `./build.sh` (add `--debug` for faster iteration or `--open` to relaunch).
- Unit tests: `swift test --scratch-path ~/Library/Developer/CropBlock/test-build`
- Self-test: `tools/selftest.sh` (runs against `/tmp/CropBlock-self-store`, exit 0 when all checks pass).
- Snapshots: `tools/snap.sh` (writes `/tmp/CropBlock-shots/<page>-light.png` and `-dark.png` plus `*-layout.json`). Limit with `APP_SNAPSHOT_PAGES=empty,detected`.
- Grid checks: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/CropBlock-shots/*-layout.json`. Both must print PASS.
- Never run snapshots or self-tests against `~/Library/Application Support/CropBlock/`. Always pass `APP_STORE` in `/tmp`.

## Design Rules

- Design rules: `design/DESIGN-SYSTEM.md`. Use its tokens; never raw colors, radii, or durations.
- Spacing comes from `Space` in `Sources/CropBlock/UI/Grid.swift` (strict 4 pt grid). Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows and sheets open calm: `.noInitialFocus()` on every window and sheet; `.fitsContent()` on sheets and Settings tabs.
- Compatibility: guard macOS 26 APIs (`glassEffect`, `ToolbarSpacer`) with `#available(macOS 26, *)` through `Sources/CropBlock/UI/Compat.swift` so macOS 15 Sequoia compiles and renders cleanly.
- Every toolbar and context menu action also lives in the menu bar with a shortcut; never rely on color alone for status badges.

## Git

- Commit after each working story with a message describing what the user can now do.
