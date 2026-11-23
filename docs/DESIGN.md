# Crop Block — Design & Architecture Plan

This document pairs with [BRIEF.md](BRIEF.md) and defines the macOS UX design plan (`mac-design`), the pure-Swift engine architecture (`CropBlockKit`), and the distribution pipeline before Milestone 1 begins.

---

## 1. Mac Design Plan

### Archetype
Two-column `NavigationSplitView` utility window + native `Settings` window (`⌘,`):
- **Left column (Queue)**: 260–340 pt resizable sidebar-style list of queued MKV files with status badges, compact resolution/AR summary, and drag-and-drop ingestion.
- **Right column (Preview & Inspector)**: Vertical split inside the detail pane:
  - **Top (~58%)**: SAR-corrected preview frame canvas with live dimmed crop overlay, crisp crop boundary, dimension pill, overlay toggle, and sample timestamp switcher (`20%` / `50%` / `80%`) so users can verify framing across multiple scenes.
  - **Bottom (~42%)**: Inline Variable-AR warning banner (when triggered), manual even-pixel offset steppers (M2), Matroska track `v1` header diff table (`Before → After`), and footer action bar (**Restore Original**, **Rescan**, prominent **Apply Crop**).

### Information Architecture
Single flat level — no synthetic folder hierarchy:
1. **Queue** (left column): All added MKV files in drop order, with live status filter pills appearing only when the queue has items (progressive disclosure).
2. **Inspector Detail** (right column): Active selection's visual preview, crop controls, and Matroska header diff.
3. **Lightweight Surfaces**:
   - **Player Compatibility Popover** (`info.circle` in detail toolbar): Explains that `PixelCrop*` headers work natively in `mpv`, `MPC-BE`, and `Kodi`, whereas `VLC` and many web/smart-TV players ignore container crop flags.
   - **Tool Setup Sheet** (non-blocking sheet on launch when any required binary is missing, or opened from toolbar badge): Status list for `ffmpeg`, `ffprobe`, `mkvpropedit`, copyable `brew install ffmpeg mkvtoolnix` command, per-tool `Browse…` button, `Re-check Tools`, and `Continue Anyway`.
   - **Settings Window (`⌘,`)**: Four content-fitted tabs (`General`, `Detection`, `Tools`, `Appearance`), following `mac-design/settings.md`.

### Command Map

| Action | Menu | Shortcut | Toolbar / Surface |
| --- | --- | --- | --- |
| Add Files… | File > Add Files… | `⌘O` | Queue toolbar (`plus`), empty state button |
| Scan Selected | Queue > Scan Selected | `⌘R` | Detail footer (`Rescan`), row context menu |
| Scan All Pending | Queue > Scan All Pending | `⇧⌘R` | Queue toolbar (`viewfinder`) |
| Stop Scanning | Queue > Stop Scanning | `⌘.` | Replaces Scan All while active |
| Apply Crop | Crop > Apply Crop | `⌘↩` | Detail footer prominent button, row context menu |
| Apply All Ready | Crop > Apply All Ready | `⇧⌘↩` | Detail toolbar (M2) |
| Restore Original | Crop > Restore Original | `⌘Z` / `⌥⌘Z` | Detail footer, row context menu |
| Toggle Crop Overlay | View > Hide/Show Crop Overlay | `Space` | Preview canvas overlay pill |
| Next / Previous Sample Frame | View > Sample Frame > 1/2/3 | `⌘1` / `⌘2` / `⌘3` | Preview frame segmented picker |
| Remove from Queue | Edit > Remove from Queue | `⌫` | Row context menu |
| Clear Completed | Queue > Clear Completed | `⌥⌘⌫` | Queue menu |
| Player Compatibility | Help > Player Compatibility | — | Detail toolbar (`info.circle` popover) |
| Tool Setup… | Crop Block > Tool Setup… | — | Onboarding sheet / missing-tool banner |
| Settings… | Crop Block > Settings… | `⌘,` | Standard Settings scene |

`SidebarCommands()` and `ToolbarCommands()` are included on the main scene. Every toolbar action has a matching menu item and `.help("Verb phrase (shortcut)")`.

### Empty States
- **Empty Queue (launch)**: Centered drop zone (`ContentUnavailableView` layout with drag-over highlight), title `"Drop MKV Files or Folders"`, description `"Crop Block detects black bars and edits Matroska headers without re-encoding."`, primary button `"Add Files…"`.
- **Queue Populated, No Selection**: `"Select a File"` with caption `"Choose an MKV file from the queue to preview its crop."`.
- **Pending Item Selected (not yet scanned)**: Preview placeholder with `"Ready to Scan"` and `"Scan Now"` button (scanning starts automatically on drop by default, configurable in Settings).
- **No Bars Detected**: Shows the clean frame with green/neutral status pill `"No Black Bars Detected"` and disabled `"Apply Crop"` (still allows manual offset entry in M2 if the user wants a custom crop).

### Feeling
**Confident, fast, and surgical.** Like a precision Apple Pro Video utility: calm neutral surfaces so cinema frames stand out, crisp monospaced numbers for every pixel offset and aspect ratio, instant visual proof before any byte on disk changes, and zero fear thanks to 1-click lossless Restore.

### macOS 15+ & macOS 26 Liquid Glass Compatibility
- `Package.swift`: `platforms: [.macOS(.v15)]`, `swift-tools-version: 6.2`.
- `Info.plist.in`: `CFBundleIdentifier = io.github.mobiusgt.cropblock`, `LSMinimumSystemVersion = 15.0`, `CFBundleDisplayName = Crop Block`, `CFBundleName = CropBlock`, `CFBundleExecutable = CropBlock`, `CFBundleDocumentTypes` registering `.mkv` (`org.matroska.mkv`) for Dock-drop and Finder "Open With". Help/About links point to `https://github.com/MobiusGT/CropBlock`.
- Thin view modifier bridge (`Sources/CropBlock/UI/Compat.swift`):
  - `#available(macOS 26, *)`: `.glassEffect(.regular, in: .capsule)`, `GlassEffectContainer`, `ToolbarSpacer(.flexible)` / `ToolbarSpacer(.fixed)`.
  - macOS 15 fallback: `.regularMaterial` capsule with subtle hairline stroke and standard toolbar spacing.
- All windows and sheets use `.noInitialFocus()`; sheets and Settings tabs use `.fitsContent()`. Strict 4 pt spacing grid via `Space` tokens (`UI/Grid.swift`) verified by `tools/grid-lint.sh` and `tools/check-layout.swift`.

### App Icon Concepts (for Milestone 2 `app-icon`)
1. **Cinema Aperture (Recommended)**: Deep slate-indigo `automatic-gradient` background; a crisp white 2.39:1 rounded cinema frame centered on top, flanked above and below by two translucent receding letterbox bars that visually convey "bars removed" — bold, geometric, recognizable at 16 px.
2. **Crop Brackets**: Graphite-blue background with four thick white corner crop marks framing a translucent widescreen matte.
3. **Matroska Frame Cut**: Indigo-teal background with a single bold widescreen viewport sitting over an indented 16:9 glass plate.

---

## 2. Technical Architecture

### Package & Module Layout
All logic lives in a SwiftUI-free library target (`CropBlockKit`) so unit tests run in seconds with Swift Testing (`swift test`):

```text
Crop Blocker/                       # Workspace root (scripts quote all paths safely)
├── Package.swift                   # .macOS(.v15), CropBlockKit + CropBlock + CropBlockKitTests
├── Info.plist.in                   # LSMinimumSystemVersion 15.0, MKV document type, AppIcon
├── build.sh                        # SwiftPM build -> CropBlock.app -> codesign -> ~/Applications
├── CLAUDE.md                       # Build, test, grid, and design rules
├── Icon/AppIcon.icon/              # Icon Composer JSON + SVG layers (M2)
├── docs/
│   ├── BRIEF.md
│   ├── DESIGN.md
│   ├── GLOSSARY.md
│   └── STORIES.md
├── design/
│   └── DESIGN-SYSTEM.md            # Token usage rules (created alongside UI tokens)
├── scripts/
│   └── release.sh                  # Universal Binary, Hardened Runtime, notarization, DMG (M2)
├── tools/                          # BAMA checks: grid-lint, check-layout, snap, selftest, icon
├── Sources/
│   ├── CropBlockKit/               # Pure Swift, Sendable, strict concurrency, zero SwiftUI
│   │   ├── Models/
│   │   │   ├── CropGeometry.swift          # CropRect, CropInsets, SAR, DisplaySize, AspectRatio
│   │   │   ├── VideoInspection.swift       # FFprobe stream info + MatroskaVideoHeader
│   │   │   ├── CropDetectionResult.swift   # SampleResult, UnionResult, VariableARWarning
│   │   │   ├── EditReceipt.swift           # Undo/Restore snapshot model
│   │   │   └── DetectionSettings.swift     # Timestamps, duration, limit, concurrency, noise floor
│   │   ├── Math/
│   │   │   └── CropCalculator.swift        # Pure deterministic crop, union, SAR, variable-AR math
│   │   ├── Matroska/
│   │   │   └── MatroskaHeaderReader.swift  # Pure-Swift EBML parser for track v1 Video headers
│   │   ├── Tools/
│   │   │   ├── ProcessRunner.swift         # Async Process wrapper with Task cancellation + pipes
│   │   │   ├── ToolResolver.swift          # Discovers ffmpeg, ffprobe, mkvpropedit
│   │   │   ├── FFprobeParser.swift         # Parses ffprobe JSON output
│   │   │   ├── CropDetectRunner.swift      # Multi-timestamp ffmpeg cropdetect + stderr parser
│   │   │   └── FrameExtractor.swift        # Extracts JPEG/PNG sample frames (-apply_cropping none)
│   │   ├── Backends/
│   │   │   ├── CropBackend.swift           # Protocol + CropApplyPlan (M3 future-ready hook)
│   │   │   └── MKVHeaderCropBackend.swift  # mkvpropedit --edit track:v1 apply & restore
│   │   └── Persistence/
│   │       └── ReceiptStore.swift          # Atomic JSON store for 1-click Undo/Restore history
│   └── CropBlock/                  # SwiftUI macOS App (@MainActor default isolation)
│       ├── App.swift                       # Main scene, Settings, menu commands, Dock drop delegate
│       ├── AppModel.swift                  # @Observable queue coordinator, bounded TaskGroup
│       ├── Snapshot.swift                  # APP_SNAPSHOT & --selftest runners
│       ├── SeedData.swift                  # Deterministic seed queue + synthetic preview frames
│       ├── Views/
│       │   ├── ContentView.swift           # 2-pane NavigationSplitView + drop target + toolbar
│       │   ├── QueueListView.swift         # File queue rows, status badges, context menu
│       │   ├── DetailWorkspaceView.swift   # Preview canvas + Variable AR banner + diff + footer
│       │   ├── PreviewCanvasView.swift     # SAR-corrected frame + live crop overlay + switcher
│       │   ├── HeaderDiffView.swift        # Grid/GridRow Before -> After Matroska properties
│       │   ├── CropOffsetsEditor.swift     # Even-pixel steppers & reset (M2)
│       │   ├── CompatibilityPopover.swift  # mpv/MPC-BE/Kodi vs VLC/TV/web note
│       │   ├── ToolOnboardingSheet.swift   # Missing-binary status, brew command copy, Browse…
│       │   └── SettingsView.swift          # General, Detection, Tools, Appearance tabs
│       └── UI/
│           ├── Theme.swift                 # System + Slate Indigo brand accent tokens
│           ├── Surfaces.swift              # Adaptive semantic surfaces, warning/status colors
│           ├── Radius.swift                # Concentric corner radii
│           ├── Motion.swift                # Reduce-Motion-aware animations
│           ├── Compat.swift                # macOS 26 Liquid Glass / macOS 15 material bridge
│           ├── Grid.swift                  # 4 pt Space scale, gridArea, gridProbe, overlay
│           ├── WindowBehavior.swift        # .noInitialFocus(), .fitsContent()
│           └── AppearanceSettings.swift    # Accent picker in Settings
└── Tests/
    └── CropBlockKitTests/          # Swift Testing (@Test) suite
        ├── CropCalculatorTests.swift       # 16:9, 2.39:1, 4:3 pillarbox, anamorphic SAR, mixed-AR
        ├── CropDetectParserTests.swift     # Real & synthetic ffmpeg stderr parsing, dark frames
        ├── MatroskaHeaderReaderTests.swift # Raw EBML fixture parsing (present vs absent elements)
        ├── MKVHeaderCommandTests.swift     # Verifies exact mkvpropedit apply & restore argv
        ├── ToolResolverTests.swift         # Precedence order & missing-binary reporting
        └── IntegrationTests.swift          # Optional live ffmpeg+mkvpropedit round-trip on temp MKV
```

### Core Technical Algorithms & Edge Cases

#### 1. Pure-Swift Matroska EBML Header Reader (`MatroskaHeaderReader`)
- Reads only the MKV `Segment → Tracks → TrackEntry (TrackType == 1) → Video` element using `FileHandle.seek` to skip `Cluster` / `Attachments` / `Tags` blocks (parses 50 GB remuxes in < 1 ms without requiring `mkvmerge` as an extra dependency).
- Parses `SeekHead` (`0x114D9B74`) → `Seek` (`0x4DBB`) → `SeekID == Tracks` (`0x1654AE6B`) → `SeekPosition` (`0x53AC`) to jump straight to `Tracks` even when a muxer placed `Tracks` at the end of the file after all `Cluster`s (with sequential seek-skipping fallback if `SeekHead` is absent).
- Captures exact optional fields (`Int?`): `pixelWidth`, `pixelHeight`, `pixelCropLeft`, `pixelCropRight`, `pixelCropTop`, `pixelCropBottom`, `displayWidth`, `displayHeight`, `displayUnit`.
- Distinguishes **absent** vs **explicitly `0`**, enabling exact restoration via `mkvpropedit --delete <prop>` vs `--set <prop>=<value>`.

#### 2. Uncropped Frame Guarantee (`-apply_cropping none`)
- When inspecting or previewing an MKV that *already* carries `PixelCrop*` headers, FFmpeg's decoder applies container cropping by default unless disabled.
- Both `CropDetectRunner` and `FrameExtractor` pass `-apply_cropping none` (or `-apply_cropping 0` validated against installed FFmpeg in M1) as an input option so detection and visual overlays always operate in the raw encoded `PixelWidth × PixelHeight` coordinate space that `mkvpropedit` expects.
- Fast keyframe seeking (`-ss <t>` placed *before* `-i <file>`) ensures multi-sample scanning completes in seconds even on large 4K files.

#### 3. Multi-Timestamp Union Bounding Box
- Default sample timestamps: `20%`, `50%`, `80%` of `duration`, `10 s` per window (clamped cleanly for short clips `< 30 s`; clips `<= 10 s` run a single sample from `0 s`).
- Each sample runs `cropdetect=limit=24:round=2:reset=0`; the last non-empty `crop=w:h:x:y` (ignoring all-black `w <= 0 || h <= 0` frames) is recorded for that sample.
- Union across all valid samples $R_i = (x_i, y_i, w_i, h_i)$:
  - $x_{\min} = \min_i x_i,\quad y_{\min} = \min_i y_i$
  - $x_{\max} = \max_i (x_i + w_i),\quad y_{\max} = \max_i (y_i + h_i)$
  - Offsets rounded conservatively **outward** to even pixels (never cropping active picture):
    - `left = floorEven(clamp(x_min, 0, W))`
    - `top = floorEven(clamp(y_min, 0, H))`
    - `right = floorEven(clamp(W - x_max, 0, W))`
    - `bottom = floorEven(clamp(H - y_max, 0, H))`
- **Sanity & Noise Guards**:
  - If all samples are solid black or `left + right >= W` or `top + bottom >= H` → treat as **No Bars** with an explanatory note (never produce a degenerate 0×0 crop).
  - Edges below a small noise floor (default `4 px`, or `0` when manually overridden) snap to `0` so 2 px compression jitter does not mark full-frame movies as letterboxed.

#### 4. Anamorphic (Non-1:1 SAR) Display Dimension Math
Cropping removes pixels without changing individual pixel shape (`SAR = sarNum / sarDen`):
- Cropped encoded size: $w_c = W - L - R$, $h_c = H - T - B$.
- **Square pixels** (`sarNum == sarDen`): `displayWidth = w_c`, `displayHeight = h_c`.
- **Wide pixels** (`sarNum > sarDen`, e.g., 16:9 NTSC DVD `720×480` SAR `32:27`, HDV `1440×1080` SAR `4:3`): preserve vertical precision (`displayHeight = h_c`) and compute `displayWidth = round(w_c * sarNum / sarDen)`.
  - Example: `720×480` SAR `32:27` cropped `T=60, B=60` (`720×360`) → `displayWidth = 853`, `displayHeight = 360` (`2.37:1`).
- **Tall pixels** (`sarNum < sarDen`, e.g., 4:3 NTSC DVD `720×480` SAR `8:9`): preserve horizontal precision (`displayWidth = w_c`) and compute `displayHeight = round(h_c * sarDen / sarNum)`.
- **SAR Fallback**: If `ffprobe` reports `N/A` or `0:1` while the original MKV header has `DisplayWidth`/`DisplayHeight` (`DisplayUnit == 0`) and zero crop, derive effective SAR from `(DisplayWidth * H) / (W * DisplayHeight)`; otherwise default to `1:1`.
- Always writes `--set display-unit=0` along with `display-width` and `display-height`.

#### 5. Mixed Aspect Ratio (Variable AR / IMAX) Detection
- Computes spread across valid non-black samples:
  - `widthSpread = max(w_i) - min(w_i)`
  - `heightSpread = max(h_i) - min(h_i)`
- Triggers **Warning: Variable AR** when `heightSpread > max(16, round(H * 0.03))` OR `widthSpread > max(16, round(W * 0.03))` (e.g., `> 32 px` on 1080p; catches IMAX 1.90:1 / 1.78:1 vs 2.39:1 shifts while ignoring 4–8 px dark-border jitter).
- Behavior:
  - Queue row displays the amber `Variable AR` badge.
  - Detail pane shows per-sample dimensions (`20%: 1920×800 · 50%: 1920×1080 · 80%: 1920×800`) and lets the user flip between all 3 extracted sample frames in the preview canvas.
  - **Apply Crop** stays disabled until the user checks `"I've verified the samples — allow crop"`, and **Apply All Ready** (M2) skips unconfirmed Variable AR files automatically.

#### 6. Lossless Header Apply & 1-Click Undo / Restore
- **Apply**:
  1. Validate file exists, is writable, and starts with EBML header `0x1A45DFA3`.
  2. Persist the original `MatroskaVideoHeader` to `~/Library/Application Support/CropBlock/receipts.json` (only overwriting if no un-restored receipt already exists for that file, so re-cropping a file preserves the *true* pre-Crop-Block original!).
  3. Execute `mkvpropedit <file> --edit track:v1 --set pixel-crop-left=L --set pixel-crop-right=R --set pixel-crop-top=T --set pixel-crop-bottom=B --set display-unit=0 --set display-width=DW --set display-height=DH`.
  4. Re-read `MatroskaHeaderReader` to verify the written header matches the plan.
- **Restore Original**:
  - If an `EditReceipt` exists: restores every original field verbatim (`--set` if originally present, `--delete` if originally absent) and removes the receipt.
  - If no `EditReceipt` exists (e.g., file was cropped externally) and the MKV currently has non-zero `PixelCrop*`: offers **"Reset Crop Headers"** which runs `--delete pixel-crop-left/right/top/bottom` and resets `display-unit=0`, `display-width`, `display-height` to the full SAR-adjusted encoded dimensions.

#### 7. Binary Resolution (`ToolResolver`)
Checks each required binary (`ffmpeg`, `ffprobe`, `mkvpropedit`) cleanly and reports resolved path, origin badge, and version string:
1. **Custom Settings path**: User-selected path stored in Settings > Tools (takes priority #1 whenever explicitly configured).
2. **Bundled helpers**: `<App>.app/Contents/Helpers/<tool>` (present in self-contained release builds).
3. **Homebrew & `$PATH`**: `/opt/homebrew/bin/<tool>`, `/usr/local/bin/<tool>`, then directories in `$PATH`.

#### 8. Background Execution & Bounded Concurrency
- `ProcessRunner` wraps `Foundation.Process` in an `async throws` API using `withTaskCancellationHandler` (terminates child process with `SIGTERM` / `SIGKILL` fallback immediately on cancellation) and drains stdout/stderr pipes concurrently on non-blocking dispatch handles so large stderr outputs from `ffmpeg` never deadlock a pipe buffer.
- `AppModel` runs batch scans and batch applies through a bounded `TaskGroup` (default concurrency: `2` scans at once, configurable `1–4` in Settings; `mkvpropedit` applies run fast in-place with bounded concurrency `2` so disk I/O stays smooth and UI stays at 60/120 fps).
- Preview frame extraction writes temporary JPEGs into a per-session cache under `NSTemporaryDirectory()/CropBlock-<pid>/` cleaned up on quit.

#### 9. Future-Ready Backend Protocol (Milestone 3 Hook)
```swift
public enum CropBackendID: String, Codable, Sendable, CaseIterable {
    case mkvHeader
    // Future: case bitstreamMetadata
}

public protocol CropBackend: Sendable {
    var id: CropBackendID { get }
    var displayName: String { get }
    func canHandle(inspection: VideoInspection) -> Bool
    func buildPlan(for inspection: VideoInspection, insets: CropInsets) -> CropApplyPlan
    func apply(plan: CropApplyPlan, to url: URL, tools: ResolvedTools) async throws -> EditReceipt
    func restore(receipt: EditReceipt?, inspection: VideoInspection, to url: URL, tools: ResolvedTools) async throws
}
```
Keeping all mutation and diff generation behind `CropBackend` means adding a lossless H.264/HEVC bitstream crop backend (`h264_metadata` / `hevc_metadata`) in Milestone 3 requires no UI or queue rewrite.

#### 10. Release Packaging (`scripts/release.sh` in Milestone 2)
- Builds Universal Binary (`--arch arm64 --arch x86_64`) via SwiftPM for GitHub Releases (`https://github.com/MobiusGT/CropBlock`).
- Compiles `Icon/AppIcon.icon` into `Assets.car` + `AppIcon.icns`.
- Optional `BUNDLE_HELPERS_DIR` env var copies self-contained `ffmpeg`, `ffprobe`, `mkvpropedit` into `Contents/Helpers/` and signs each binary individually.
- Uses **ad-hoc signing by default** (`codesign --force --sign -`) so a Universal `.dmg` builds cleanly with zero Apple Developer account required.
- When `DEVELOPER_ID` is provided, switches to Hardened Runtime (`--options runtime --timestamp`) signing; when `NOTARY_PROFILE` is also set, submits via `xcrun notarytool submit --wait` and staples with `xcrun stapler staple`.
- Creates a clean `.dmg` with `/Applications` symlink via `hdiutil`.
