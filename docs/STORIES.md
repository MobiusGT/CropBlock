# User Stories & Milestone Plan

Built from [BRIEF.md](BRIEF.md) and [DESIGN.md](DESIGN.md). Terms follow [GLOSSARY.md](GLOSSARY.md).
Acceptance tags: `[unit]` Swift Testing, `[snap]` light & dark snapshot + grid check, `[self]` `--selftest`, `[manual]` hands-on check.

---

## Milestone 1 — MVP (Core Detection, Visual Verification & Lossless Header Edit)

Goal: End-to-end native macOS app supporting macOS 15+ (with macOS 26 Liquid Glass where available) that discovers tools, ingests MKV files, detects black bars accurately across multiple timestamps, previews the SAR-corrected crop overlay + Matroska header diff, and losslessly applies or restores edits in-place.

### S-001 Scaffold native macOS 15+ SwiftPM app & design tokens
As a developer and user, Crop Block builds as a native `.app` bundle targeting macOS 15+ with conditional macOS 26 Liquid Glass styling, strict 4 pt spacing tokens, light/dark snapshot mode, and a passing self-test harness.
Screens: `empty-light.png`, `empty-dark.png`
Acceptance:
- [unit] `swift test` builds and passes `CropBlockKitTests` on macOS 15+ deployment target (`Package.swift` `.macOS(.v15)`).
- [snap] `./build.sh` installs `~/Applications/CropBlock.app` (`LSMinimumSystemVersion` = `15.0`); empty window snapshots render cleanly in light and dark mode with zero focus ring and `tools/grid-lint.sh` + `tools/check-layout.swift` PASS.
- [self] `tools/selftest.sh` passes smoke checks and validates every SF Symbol name.
UX:
- Flow: Launch app -> calm 2-pane split window opens with empty Queue drop zone -> `⌘Q` quits cleanly
- Surface: Main window (`NavigationSplitView`, two columns)
- States: Empty Queue shows `"Drop MKV Files or Folders"` with `"Add Files…"` primary button
- Words: Window title `"Queue"`, subtitle `"0 files"`, button `"Add Files…"`
- Access: `.noInitialFocus()` on launch; keyboard-navigable toolbar and empty-state button; VoiceOver reads drop zone and subtitle
Status: done

### S-002 Resolve external CLI tools & show non-blocking Tool Setup sheet
As the user, Crop Block automatically locates `ffmpeg`, `ffprobe`, and `mkvpropedit` (Custom Settings path → Bundled `Contents/Helpers/` → Homebrew & `$PATH`), and shows a friendly non-blocking setup sheet when any tool is missing.
Screens: `setup-light.png`, `setup-dark.png`
Depends: S-001
Acceptance:
- [unit] `ToolResolverTests` verifies discovery precedence, missing-tool reporting, and non-executable path rejection.
- [snap] Tool Setup sheet renders in light/dark mode with green/red status icons + labels (never color alone), copyable `brew install ffmpeg mkvtoolnix` row, per-tool `Browse…`, `Re-check Tools`, and `Continue Anyway`, sized with `.fitsContent()`.
- [self] Missing-tool state exposes actionable status in `AppModel`; dismissing the sheet leaves the main window usable.
UX:
- Flow: Launch with missing tool (or Crop Block > Tool Setup…) -> Tool Setup sheet opens -> Copy Homebrew command or Browse… -> Re-check Tools -> sheet dismisses when ready (or Continue Anyway / Escape dismisses anytime)
- Surface: Sheet (one short task that can finish or cancel before going on)
- States: Missing tool shows red icon + `"Not Found"` + `Browse…`; found tool shows green checkmark + resolved path + origin badge (`Bundled`, `Homebrew`, `PATH`, `Custom`); Copy button flashes `"Copied"`
- Words: Title `"Tool Setup"`, copyable command `"brew install ffmpeg mkvtoolnix"`, buttons `"Copy Command"`, `"Browse…"`, `"Re-check Tools"`, `"Continue Anyway"`
- Access: `.noInitialFocus()`, Escape dismisses, VoiceOver reads tool name, status, and path
Status: done

### S-003 Pure-Swift crop math, EBML header reader & detection unit tests
As the user, Crop Block computes accurate union bounding boxes, even-pixel MKV crop offsets, SAR-adjusted display dimensions, and Variable AR warnings without over-cropping dark scenes or distorting anamorphic video.
Screens: none (logic library `CropBlockKit`)
Depends: S-001
Acceptance:
- [unit] `CropCalculatorTests` covers: standard 16:9 (no bars), 2.39:1 letterbox on 1080p & 4K, 4:3 pillarbox on 1080p, dark-scene union bounding box preventing over-crop, wide anamorphic SAR (720×480 SAR 32:27, 1440×1080 SAR 4:3), tall anamorphic SAR (720×480 SAR 8:9), mixed-AR / IMAX warning trigger & non-trigger jitter, all-black frame safety guard, and minimum noise-floor threshold.
- [unit] `CropDetectParserTests` parses real & synthetic `ffmpeg` stderr output including dark fades and missing fields.
- [unit] `MatroskaHeaderReaderTests` parses EBML track `v1` video headers (both `Tracks` before `Cluster` and `Tracks` at end of file via `SeekHead`) and accurately distinguishes absent vs. zero crop/display fields.
- [unit] `MKVHeaderCommandTests` verifies exact `mkvpropedit` argv for apply, receipt-based restore (`--set` vs `--delete`), receipt-less reset, and graceful per-file error mapping for read-only / SMB / NFS I/O failures.
Status: done

### S-004 Add MKV files & folders to the Queue via drag-and-drop, File panel, or Dock icon
As the user, I drop MKV files or folders onto the window (or Dock icon) or press `⌘O` to populate the Queue with deduplicated `.mkv` files and inspect their live status badges.
Screens: `detected-light.png`, `detected-dark.png`
Depends: S-001, S-002
Acceptance:
- [unit] Folder scanner recursively finds `.mkv` files (case-insensitive), skips hidden files/directories and non-MKV files, deduplicates by canonical URL, and disambiguates duplicate filenames with parent-folder context.
- [snap] Queue displays realistic seed files showing all status badges (`Pending`, `Detected`, `No Bars`, `Variable AR`, `Cropped`, `Error`), monospaced resolution/AR subtitle, and selection highlight in light & dark mode; grid checks PASS.
- [self] Adding files updates Queue count; Delete (`⌫`) removes the selected file and moves selection to the next row; `NSApp.mainMenu` audit verifies menu commands and shortcuts.
- [manual] Dragging an `.mkv` file or folder from Finder onto the window or Dock icon populates the Queue.
UX:
- Flow: Drop files/folders onto window or Dock, or press `⌘O` / toolbar `+` -> MKV files appear in Queue -> first item selects automatically -> Delete removes from Queue (never deletes from disk)
- Surface: Sidebar Queue column in `NavigationSplitView` + row `.contextMenu`
- States: Empty drop zone highlights with accent border on drag-over; non-MKV-only drop shows calm inline banner `"No MKV files found in dropped items"`; long filenames middle-truncate with full path tooltip
- Words: `"Add Files…"` (`⌘O`), `"Remove from Queue"` (`⌫`), `"Reveal in Finder"`, tooltip `"Add MKV files or folders to the queue (⌘O)"`
- Access: Arrow keys move selection, Delete removes, every badge pairs SF Symbol + text label, VoiceOver announces filename, resolution, and status
Status: done

### S-005 Background `ffprobe` + multi-timestamp `cropdetect` engine with cancellation
As the user, queued files scan automatically in the background across multiple timestamps (`20%`, `50%`, `80%`, 10 s each) using bounded concurrency without freezing the UI, and I can cancel or rescan any file.
Screens: `detected-light.png`
Depends: S-002, S-003, S-004
Acceptance:
- [unit] `ProcessRunner` cancels an active child process cleanly when its Swift `Task` is cancelled and never deadlocks on large stderr output.
- [unit] Live integration test (skipped gracefully if tools absent) generates a synthetic 16:9 MKV with baked-in black bars via `ffmpeg`, scans it, and detects exact `top`/`bottom` offsets within 2 px even after `mkvpropedit` has already cropped it (`-apply_cropping none`).
- [self] Scanning transitions status `Pending` → `Scanning` → `Detected` / `No Bars` / `Variable AR` / `Error`; `Stop Scanning` (`⌘.`) cancels active scans cleanly.
UX:
- Flow: Files enter Queue -> bounded background scan starts (or press `⌘R` / `⇧⌘R`) -> row shows inline progress spinner -> transitions to result badge -> `⌘.` cancels in-flight scans
- Surface: Inline row status + toolbar `Scan All` / `Stop` toggle button
- States: Scanning shows compact inline `ProgressView` + `"Scanning…"`; Error shows red `Error` badge and inline actionable error card in detail pane with `"Rescan"` button
- Words: `"Scan Selected"` (`⌘R`), `"Scan All Pending"` (`⇧⌘R`), `"Stop Scanning"` (`⌘.`), tooltip `"Scan all pending files for black bars (⇧⌘R)"`
- Access: Status transitions readable by VoiceOver; cancel available via keyboard `⌘.`
Status: done

### S-006 Visual preview frame with SAR-corrected crop overlay & sample switcher
As the user, I visually inspect an extracted sample frame for the selected file with dimmed crop bars, a crisp crop boundary, exact `L/R/T/B` offsets, and original vs. cropped resolution and aspect ratio before writing any header.
Screens: `detected-light.png`, `detected-dark.png`, `variable-ar-light.png`, `variable-ar-dark.png`
Depends: S-004, S-005
Acceptance:
- [snap] Detail preview renders the frame at its SAR-corrected aspect ratio with dimmed crop bars, crisp crop boundary, floating dimension pill over a dark scrim, overlay visibility toggle, and `20% / 50% / 80%` sample switcher in light & dark mode; grid checks PASS.
- [self] Switching sample timestamps updates the displayed frame index; pressing `Space` toggles the crop overlay visibility.
UX:
- Flow: Select scanned file -> Preview shows 50% Sample Frame with Crop Overlay -> click `20%` / `50%` / `80%` (or `⌘1`/`⌘2`/`⌘3`) to check other timestamps -> press `Space` to compare with/without overlay
- Surface: Top region of Detail pane (inspector detail view)
- States: Pending shows placeholder + `"Scan Now"`; Scanning shows centered progress indicator `"Extracting preview…"`; No Bars shows clean uncropped frame with `"No Black Bars Detected"` capsule; Variable AR uses amber crop boundary until confirmed
- Words: `"20%"`, `"50%"`, `"80%"`, `"Hide Crop Overlay"` / `"Show Crop Overlay"` (`Space`), tooltip `"Toggle crop overlay visibility (Space)"`
- Access: Capsule text sits over dark scrim for >= 4.5:1 contrast in both modes; keyboard shortcuts `Space`, `⌘1–3`; VoiceOver describes cropped dimensions and offsets
Status: done

### S-007 Matroska header diff inspector, Variable AR confirmation & Player Compatibility popover
As the user, I review the exact Matroska track `v1` before-and-after header diff, explicitly confirm any Variable AR warning before applying, and can check player compatibility from a subtle toolbar info popover.
Screens: `detected-light.png`, `variable-ar-light.png`, `compatibility-light.png`, `compatibility-dark.png`
Depends: S-006
Acceptance:
- [snap] Header Diff `Grid` displays aligned monospaced before → after values (`pixel-crop-left/right/top/bottom`, `display-width × display-height`, `display-unit`, effective AR, and SAR badge when non-1:1); Variable AR banner lists per-sample rects with a required confirmation toggle; Player Compatibility popover renders cleanly in light & dark mode.
- [self] For a `Variable AR` file, `canApply` is `false` until the user confirms; toggling confirmation enables `Apply Crop`.
UX:
- Flow: Inspect Header Diff below preview -> if Variable AR, inspect sample rects & toggle `"Allow crop despite variable aspect ratio"` -> click toolbar `info.circle` anytime to view Player Compatibility popover -> Escape closes popover
- Surface: Bottom region of Detail pane (inline diff + warning banner) and Popover (`info.circle`, tied to one control)
- States: Non-1:1 SAR displays explicit note (e.g., `"Anamorphic SAR 32:27 applied"`); Variable AR banner highlights disagreeing timestamps inline in amber with warning icon
- Words: `"Matroska Header Changes (track:v1)"`, `"Variable Aspect Ratio Detected"`, `"Allow crop despite variable aspect ratio"`, popover title `"Player Compatibility"` noting `mpv`, `MPC-BE`, and `Kodi` support vs. `VLC` and web/TV clients ignoring `PixelCrop*`
- Access: Warning uses icon + title + text (not color alone); monospaced digits align cleanly in `GridRow`; popover closes on Escape
Status: done

### S-008 Lossless in-place Apply Crop & 1-Click Restore Original (via `CropBackend` protocol)
As the user, I click **Apply Crop** (`⌘↩`) to losslessly update the MKV header in-place via `MKVHeaderCropBackend` (`mkvpropedit`), and can reverse any edit with **Restore Original** (`⌘Z` / button) even after restarting the app.
Screens: `cropped-light.png`, `cropped-dark.png`
Depends: S-003, S-005, S-007
Acceptance:
- [unit] End-to-end integration test applies crop to a real temp MKV via `MKVHeaderCropBackend`, verifies `MatroskaHeaderReader` reads back exact `pixel-crop-*` and `display-width/height/unit`, restores from `ReceiptStore`, and verifies every field returns to its original state (including absent elements deleted).
- [unit] Receipt-less restore resets `pixel-crop-*` (deleted) and restores full SAR-adjusted display dimensions.
- [snap] Cropped file shows green `Cropped` badge in Queue, updated Header Diff showing current applied values, and enabled `"Restore Original"` button in light & dark mode.
- [self] Applying crop updates status to `Cropped` and records receipt; restoring reverts status and removes receipt.
UX:
- Flow: Verify preview & diff -> click `"Apply Crop"` (`⌘↩`) -> in-place header write completes in < 1s -> badge turns `Cropped` -> click `"Restore Original"` anytime to reverse losslessly
- Surface: Inline detail footer action bar (one prominent primary button `"Apply Crop"`, secondary `"Restore Original"` and `"Rescan"`)
- States: Applying shows inline button progress; read-only/missing file shows inline error `"Unable to edit file: check file permissions"` without crashing; file cropped externally shows `"Reset Crop Headers"`
- Words: `"Apply Crop"` (`⌘↩`), `"Restore Original"`, `"Reset Crop Headers"`, `"Rescan"` (`⌘R`), tooltips with verb + shortcut
- Access: `⌘↩` triggers Apply Crop when enabled; disabled cleanly for `No Bars`, `Error`, `Scanning`, or unconfirmed `Variable AR`
Status: done

---

## Milestone 2 — Polish, Batch Workflow, Settings, App Icon & Distribution

Goal: Complete batch processing, manual even-pixel fine-tuning, full Settings window, native Icon Composer app icon, light/dark + layout-grid audit across every surface, and Universal Binary notarized DMG release script.

*(UX blocks for M2 stories are written via `ux-design` just before each story enters `doing` in `improve-loop`.)*

### S-009 Manual even-pixel crop offset fine-tuning
As the user, I adjust Top, Bottom, Left, and Right crop offsets in 2 px steps (or type even values directly) and see the live preview overlay and Matroska Header Diff update immediately, with a 1-click Reset to Detected option.
Screens: `detected-light.png`, `detected-dark.png`
Depends: S-006, S-007, S-008
Acceptance:
- [unit] Clamping logic enforces even integers `>= 0`, prevents `left + right >= W` or `top + bottom >= H`, and recalculates active display AR live.
- [snap] Four aligned stepper fields (`Top`, `Bottom`, `Left`, `Right`) sit on the 4 pt grid in the detail inspector with `"Reset"` button when modified; grid checks PASS.
- [self] Stepping Top by `+2` updates active insets and marks the crop as manually adjusted; clicking `"Reset"` restores detected offsets.
UX:
- Flow: Select scanned file -> adjust Top/Bottom/Left/Right via `±2 px` steppers or numeric entry -> preview overlay and Header Diff update live -> click `"Reset"` to revert to detected offsets
- Surface: Inline compact card above Header Diff in the detail workspace (edits values on screen while watching the preview)
- States: Default matches detected values; adjusted shows `"Adjusted"` capsule and `"Reset"` button; values clamp cleanly to even integers
- Words: `"Crop Offsets"`, `"Top"`, `"Bottom"`, `"Left"`, `"Right"`, `"Adjusted"`, `"Reset"`
- Access: Keyboard Tab & arrow stepping; VoiceOver labels each edge and pixel count
Status: done

### S-010 Batch Apply All Ready with progress & Variable AR safety skip
As the user, I click **Apply All Ready** (`⇧⌘↩`) to losslessly crop every `Detected` (and explicitly confirmed `Variable AR`) file in the Queue in parallel while automatically skipping `No Bars`, `Error`, and unconfirmed `Variable AR` files.
Screens: `detected-light.png`, `detected-dark.png`
Depends: S-008
Acceptance:
- [unit] `BatchApplyPlanner` includes only `Detected` and confirmed `Variable AR` items with non-zero insets, never unconfirmed `Variable AR`, `No Bars`, `Error`, `Pending`, `Scanning`, or already `Cropped`.
- [snap] Detail toolbar displays `"Apply All Ready"` with ready count cleanly on the 4 pt grid in light & dark mode.
- [self] Batch apply processes multiple ready files, skips unconfirmed `Variable AR` and `No Bars`, isolates per-file errors, and records a restore receipt per cropped file.
UX:
- Flow: Drop folder of MKVs -> auto-scan completes -> click toolbar `"Apply All Ready (N)"` or press `⇧⌘↩` -> bounded parallel apply updates badges to `Cropped` -> inline banner reports summary (with `"Stop"` button to cancel mid-batch)
- Surface: Detail toolbar button + Crop menu item (`⇧⌘↩`) + inline progress/banner
- States: Hidden/disabled when 0 ready; enabled with ready count when >= 1 ready; active shows `"Applying X of Y…"` + `"Stop"`; finished shows calm dismissible banner
- Words: `"Apply All Ready"`, `"Stop Applying"`, tooltip `"Apply crop headers to all ready files in the queue (⇧⌘↩)"`
- Access: `⇧⌘↩` shortcut; VoiceOver announces ready count and batch completion summary
Status: done

### S-011 Native Settings window (General, Detection, Tools, Appearance)
As the user, I open Settings (`⌘,`) to configure sampling timestamps (default `20%, 50%, 80%`), sample duration (`10 s`), `cropdetect` limit (`24`), scan concurrency, auto-scan on drop, custom tool binary paths with Browse…, and app accent color.
Screens: `settings-general-light.png`, `settings-detection-light.png`, `settings-tools-light.png`, `settings-appearance-light.png` (and dark variants)
Depends: S-002, S-005
Acceptance:
- [unit] Settings persistence round-trips cleanly and validates bounds (percentages 1–99%, duration 1–60 s, limit 0–255, noise floor 0–32, concurrency 1–4).
- [snap] All 4 Settings tabs render as content-fitted grouped Forms (`.fitsContent()`) in light and dark mode with no scroll bars on short content and zero focus rings; grid checks PASS.
- [self] Changing custom tool path triggers `ToolResolver` re-evaluation; updating detection settings persists and resets cleanly.
UX:
- Flow: Press `⌘,` or Crop Block > Settings… -> switch among General, Detection, Tools, Appearance -> changes apply immediately and persist -> `⌘W` closes Settings
- Surface: Native macOS `Settings` window with 4 tabs, one grouped `Form` per tab (`.fitsContent()`)
- States: Tools tab shows live Found/Not Found icon + source badge + `Clear` button only when a custom path is set; General tab disables `"Clear Saved Receipts"` when 0 receipts exist
- Words: Tabs `"General"`, `"Detection"`, `"Tools"`, `"Appearance"`; buttons `"Reset Detection Defaults"`, `"Browse…"`, `"Clear"`, `"Re-check Tools"`, `"Copy Command"`
- Access: `.noInitialFocus()`, keyboard-navigable steppers and toggles, VoiceOver reads every setting label and value
Status: done

### S-012 Liquid Glass App Icon (Icon Composer)
As the user, Crop Block has a crafted multi-layer Icon Composer icon (`Icon/AppIcon.icon`) that reads clearly in Default, Dark, Tinted, and Clear appearances and at 16 px in Finder and the Dock.
Screens: `/tmp/CropBlock-icon.png`
Depends: S-001
Acceptance:
- [snap] `tools/make_icon.sh` writes `Resources/Assets.car` and `Resources/AppIcon.icns` with zero errors; `tools/icon_review.sh` contact sheet shows a clear custom-drawn glyph (zero SF Symbols) across Default, Dark, Tinted, Clear, 32 px, and 16 px.
- [manual] `./build.sh --open` displays the crisp icon in the Dock and Finder.
Status: todo

### S-013 Universal Binary & GitHub Releases DMG packaging script
As the maintainer, I run `scripts/release.sh` to build a Universal Binary (`arm64` + `x86_64`) `.app` bundle and distributable `.dmg` with ad-hoc signing by default (no Apple Developer account required), while supporting optional `BUNDLE_HELPERS_DIR`, Developer ID Hardened Runtime signing (`DEVELOPER_ID`), and `notarytool` notarization + stapling (`NOTARY_PROFILE`).
Screens: none (CLI build script)
Depends: S-012
Acceptance:
- [unit] `scripts/release.sh` executes cleanly with default ad-hoc signing on this Mac, produces a valid Universal (`arm64` + `x86_64`) `CropBlock.app` verified by `lipo -info` and a mountable `.dmg` verified by `hdiutil verify`.
- [manual] Optional `DEVELOPER_ID`, `NOTARY_PROFILE`, and `BUNDLE_HELPERS_DIR` branches are documented and shell-checked (`zsh -n`).
Status: todo

### S-014 Full light/dark visual polish, accessibility & milestone architecture check-in
As the user, every screen, sheet, popover, and Settings tab passes `build-and-verify`, `layout-grid`, VoiceOver/keyboard navigation checks, and `improve-architecture` check-in.
Screens: full snapshot set in light and dark (including `-AppleShowScrollBars Always`)
Depends: S-009, S-010, S-011, S-012, S-013
Acceptance:
- [snap] Every snapshot page renders cleanly in light & dark mode; `tools/grid-lint.sh`, `tools/check-layout.swift`, and design-system token grep all PASS with 0 violations.
- [self] Full `swift test` and `tools/selftest.sh` pass with 0 failures.
Status: todo

---

## Milestone 3 — Future-Ready Architecture Hook

### S-015 Verify `CropBackend` extensibility for future bitstream crop mode
As the maintainer, the cropping backend abstraction (`CropBackend` protocol + `CropApplyPlan` + `CropBackendID`) is decoupled from SwiftUI views and `AppModel`, with a mock alternate backend test proving a second backend (`h264_metadata` / `hevc_metadata`) plugs in without UI refactoring.
Screens: none (architecture & test verification)
Depends: S-014
Acceptance:
- [unit] `CropBackendProtocolTests` exercises `AppModel`/planner against both `MKVHeaderCropBackend` and a stub `BitstreamCropBackend` (`h264`/`hevc` eligibility check + plan generation) without changing UI contracts.
Status: todo

---

## Later (Out of Scope for v1)
- Lossless H.264/HEVC bitstream SPS cropping backend (`ffmpeg -c copy -bsf:v h264_metadata=...` / `hevc_metadata=...`) for players like VLC and TV clients that ignore Matroska `PixelCrop*` headers.
- Watch folder / CLI automation (`cropblock scan/apply`).
- Quick Look / side-by-side zoomed edge loupe for 1-pixel inspection.

## Dropped (Will Not Build)
- User accounts, login, telemetry, analytics, or update nagging servers (local-only native Mac utility).
- Lossy video re-encoding / transcoding (Crop Block is strictly lossless).
- MP4 / MOV / AVI containers (MKV-focused by design).
