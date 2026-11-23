# Crop Block

A lightweight native macOS utility that detects black letterbox and pillarbox bars in MKV files and removes them losslessly in-place by updating Matroska video header crop tags.

## Replaces

Running ad-hoc `ffmpeg -vf cropdetect` and `mkvpropedit` commands in Terminal by hand, or re-encoding whole movies just to strip baked-in black bars.

## Main jobs

1. Queue MKV files or folders via drag-and-drop and automatically detect black bars across multiple timestamps using `ffprobe` and `ffmpeg` (`cropdetect`), flagging variable aspect ratios (e.g., IMAX scenes).
2. Visually verify the proposed crop over an extracted SAR-corrected preview frame alongside the exact Matroska header diff (`pixel-crop-*`, `display-width`, `display-height`), with optional even-pixel fine-tuning.
3. Apply lossless in-place header edits via `mkvpropedit` (single file or batch) and reverse any edit with 1-click Undo / Restore.

## Data

- `QueueItem`: file URL, file size, `VideoInspection`, detected `CropProposal`, optional manual `CropInsets` override, `QueueItemStatus`, sample preview thumbnails, last error.
- `VideoInspection`: encoded `width` × `height`, `SAR`, `duration`, codec name, raw `MatroskaVideoHeader` snapshot before edits.
- `EditReceipt`: canonical file path, original `MatroskaVideoHeader` (preserving presence vs. absence of every header field), applied `CropInsets`, applied display dimensions, timestamp (persisted locally in Application Support for restart-safe Restore).
- `AppPreferences`: sample percentages (default `20%, 50%, 80%`), sample duration (`10s`), `cropdetect` limit (`24`), max concurrent scans, custom binary paths, appearance accent.

## Shape

Two-pane `NavigationSplitView` window (file queue on the left, visual crop preview + header diff inspector on the right) plus a native Settings window (`⌘,`). Supports macOS 15+ (Sequoia) with conditional macOS 26 (Tahoe) Liquid Glass styling. Local-only. Works offline. No accounts, no telemetry.

## System hooks

- Drag-and-drop MKV files and folders onto the window or Dock icon (`CFBundleDocumentTypes` for `.mkv`).
- Native macOS menu bar with full keyboard shortcuts (`⌘O`, `⌘R`, `⌘↩`, `⌘Z`, `⌘,`).
- Reveal in Finder from row context menu.

## Reference

None (native macOS pro utility; follows Apple HIG and BAMA `mac-design` / `layout-grid`).

## Look

Native macOS chrome with neutral translucent surfaces so the video preview frame stays the visual hero. Accent defaults to `system` (following macOS settings), with a subtle Slate Indigo brand fallback when macOS is set to Multicolor. Strict 4 pt grid alignment; full Light, Dark, and Increase Contrast support.

## Not in version one

- Re-encoding or transcoding video streams (always lossless metadata-only in v1).
- Non-MKV containers (MP4/MOV/AVI).
- H.264/HEVC bitstream SPS cropping (`h264_metadata`/`hevc_metadata`) — architecture reserves a `CropBackend` protocol hook for Milestone 3.
- Cloud sync, watch folders, or automatic recursive library daemons.

---

*Detailed architecture, macOS 15/26 design plan, and user stories live in [DESIGN.md](DESIGN.md), [GLOSSARY.md](GLOSSARY.md), and [STORIES.md](STORIES.md).*
