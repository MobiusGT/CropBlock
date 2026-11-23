# Glossary

Every user-facing noun and verb in Crop Block uses one consistent term across menus, buttons, badges, tooltips, settings, and error messages.

## Nouns

| Term | Means | Not |
| --- | --- | --- |
| Queue | The list of MKV files added to the window for scanning and cropping | list, batch, workspace, playlist |
| File | One queued `.mkv` video entry | item, task, job, video, track |
| Crop Offsets | The four even-pixel margins removed from the encoded frame (`Left`, `Right`, `Top`, `Bottom`) | margins, padding, bounds, insets |
| Sample Frame | A still image extracted at one of the sampled timestamps (`20%`, `50%`, `80%`) | thumbnail, snapshot, screenshot |
| Crop Overlay | The dimmed black-bar mask and crop boundary drawn over the Sample Frame | mask, guide, wireframe, box |
| Header Diff | The before-and-after table of Matroska `track:v1` `pixel-crop-*` properties (display dimensions remain untouched) | metadata table, diff log, inspector table |
| Variable AR | Warning state when sampled timestamps disagree significantly on active video width or height (e.g., IMAX scenes) | mixed ratio, aspect mismatch, unstable crop |
| Receipt | The saved snapshot of a file's original Matroska header fields used for Restore Original | backup, history record, log |
| Tools | The external CLI binaries required by Crop Block (`ffmpeg`, `ffprobe`, `mkvpropedit`) | dependencies, binaries, helpers, executables |

## Status Badges

Every status badge pairs a consistent label with an SF Symbol (never color alone):

| Badge | Symbol | Means |
| --- | --- | --- |
| Pending | `clock` | Queued, not yet scanned |
| Scanning | `ProgressView` | Currently running `ffprobe` / `cropdetect` / preview extraction |
| Detected | `crop` | Consistent black bars detected; ready to apply |
| No Bars | `checkmark.circle` | Active video fills the frame; no crop needed |
| Variable AR | `exclamationmark.triangle.fill` | Sampled timestamps disagree; requires explicit confirmation |
| Cropped | `checkmark.seal.fill` | Matroska header updated in-place |
| Error | `xmark.octagon.fill` | Scan or edit failed; inline message explains why and how to fix |

## Verbs (Actions)

| Term | Means | Not |
| --- | --- | --- |
| Add Files… | Open a file panel to add MKV files or folders to the Queue | Import, Load, Browse MKVs |
| Scan | Inspect a file with `ffprobe`, run multi-timestamp `cropdetect`, and extract sample frames | Analyze, Detect, Probe, Process |
| Rescan | Run Scan again on a selected file using current Detection settings | Re-analyze, Refresh, Retry |
| Apply Crop | Write Matroska crop and display-dimension headers in-place with `mkvpropedit` | Save, Commit, Export, Crop Now |
| Apply All Ready | Apply Crop to every `Detected` (and confirmed `Variable AR`) file in the Queue | Batch Run, Process All, Execute Queue |
| Restore Original | Revert a file's Matroska header fields back to its saved pre-edit state | Undo Crop, Revert File, Strip Crop |
| Reset Crop Headers | Remove `pixel-crop-*` headers and reset display dimensions when no local Receipt exists | Clear Metadata, Uncrop |
| Remove from Queue | Remove a file from the Queue without touching the file on disk | Delete, Trash, Clear File |
| Reveal in Finder | Select the MKV file in Finder | Show File, Open Folder |
| Tool Setup… | Open the onboarding sheet showing `ffmpeg`, `ffprobe`, and `mkvpropedit` status | Fix Dependencies, Install Tools |
