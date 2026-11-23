import SwiftUI
import CropBlockKit

struct DetailWorkspaceView: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    private var usesCompactPreview: Bool {
        item.status == .variableAR || (item.shouldSuggestDeepScan && item.status != .variableAR)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    headerSummary
                        .gridProbe("fileHeader", area: "detail")

                    PreviewCanvasView(item: item, compactHeight: usesCompactPreview)
                        .gridProbe("previewCanvas", area: "detail")

                    if item.status == .variableAR, let detection = item.detection {
                        variableARBanner(detection: detection)
                            .gridProbe("variableARBanner", area: "detail")
                    } else if item.shouldSuggestDeepScan, let detection = item.detection {
                        framingSuggestionBanner(detection: detection)
                            .gridProbe("framingBanner", area: "detail")
                    }

                    if let err = item.status.errorMessage {
                        errorBanner(message: err)
                            .gridProbe("errorBanner", area: "detail")
                    }

                    if let inspection = item.inspection, let plan = model.plan(for: item) {
                        CropOffsetsEditor(item: item, inspection: inspection)
                            .gridProbe("offsetsEditor", area: "detail")

                        HeaderDiffView(
                            inspection: inspection,
                            plan: plan,
                            isCropped: item.status == .cropped
                        )
                        .gridProbe("headerDiff", area: "detail")
                    }
                }
                .padding(Space.margin)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .gridArea("detail", inset: Space.margin)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            footerActionBar
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.md)
        }
    }

    private var headerSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.url.path)

                if let inspection = item.inspection {
                    HStack(spacing: Space.sm) {
                        Text(inspection.codecName.uppercased())
                        Text("·")
                        Text(formatDuration(inspection.duration))
                        Text("·")
                        Text(ByteCountFormatter.string(fromByteCount: inspection.fileSize, countStyle: .file))
                        if !inspection.sar.isSquare {
                            Text("·")
                            Text("SAR \(inspection.sar.formatted)")
                        }
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                } else {
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: Space.sm)

            if let deepLabel = item.deepScanBadgeLabel {
                Label(deepLabel, systemImage: "scope")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.accentText)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 2)
                    .background(Palette.accent.opacity(0.14), in: Capsule())
            }

            StatusBadge(status: item.status)
        }
    }

    private func variableARBanner(detection: CropDetectionResult) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        let displayedSamples = detection.previewableSamples
        let summary = displayedSamples.map { sample -> String in
            if let rect = sample.detectedRect {
                return "\(sample.window.label): \(rect.width)×\(rect.height)"
            }
            return "\(sample.window.label): black"
        }.joined(separator: "  ·  ")

        let plannedDeepCount = item.inspection.map {
            CropCalculator.deepScanIntervalCount(durationSeconds: $0.duration)
        } ?? 10

        return VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Surface.warning)
                Text("Variable Aspect Ratio Detected")
                    .font(.headline)
                Spacer()
                if let info = detection.variableAR {
                    Text("Spread: \(max(info.widthSpread, info.heightSpread)) px")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Surface.warning)
                }
            }

            Text(
                detection.isDeepScanned
                    ? "Verified across \(detection.samples.count) Deep Scan intervals — active framing varies across scenes (common in IMAX releases). Crop Block computed the conservative union bounding box so wider scenes are not cut off."
                    : "Sampled timestamps disagree on active video dimensions (common in IMAX releases). Run a \(plannedDeepCount)-interval Deep Scan to verify across the full timeline, or inspect the sample frames above before applying."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(summary)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)

            HStack(spacing: Space.md) {
                Toggle(
                    "Allow crop despite variable aspect ratio",
                    isOn: Binding(
                        get: { item.variableARConfirmed },
                        set: { model.setVariableARConfirmed($0, for: item.id) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.callout.weight(.medium))

                Spacer(minLength: Space.sm)

                if !detection.isDeepScanned {
                    Button("Run Deep Scan", systemImage: "scope") {
                        model.deepScanItem(id: item.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(item.status == .scanning || item.isApplying)
                    .help("Scan \(plannedDeepCount) intervals across the timeline (⌥⌘R)")
                }
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.warningTint, in: shape)
        .overlay(shape.strokeBorder(Surface.warning.opacity(0.4), lineWidth: 1))
    }

    private func framingSuggestionBanner(detection: CropDetectionResult) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        let plannedDeepCount = item.inspection.map {
            CropCalculator.deepScanIntervalCount(durationSeconds: $0.duration)
        } ?? 10

        let detailText: String
        if let variance = detection.framingVariance {
            switch variance.kind {
            case .edgeJitter:
                detailText = "Standard samples shifted by \(variance.maxEdgeShift) px across the timeline (common in film transfers and gate weave). Run a \(plannedDeepCount)-interval Deep Scan to lock in a safe union crop."
            case .blackSamples:
                let n = variance.blackSampleCount
                detailText = "\(n) standard \(n == 1 ? "sample" : "samples") landed on a pure-black scene. Run a \(plannedDeepCount)-interval Deep Scan to verify active framing across the full video."
            case .variableAR:
                detailText = "Run a \(plannedDeepCount)-interval Deep Scan to verify active framing across the full video."
            }
        } else {
            detailText = "Standard samples landed on pure-black frames. Run a \(plannedDeepCount)-interval Deep Scan to inspect the full timeline."
        }

        return HStack(alignment: .center, spacing: Space.md) {
            Image(systemName: "scope")
                .font(.title3)
                .foregroundStyle(Palette.accentText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Inconsistent Framing Detected")
                    .font(.headline)
                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.sm)

            Button("Run Deep Scan", systemImage: "scope") {
                model.deepScanItem(id: item.id)
            }
            .buttonStyle(.bordered)
            .disabled(item.status == .scanning || item.isApplying)
            .help("Scan \(plannedDeepCount) intervals across the timeline (⌥⌘R)")
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.08), in: shape)
        .overlay(shape.strokeBorder(Palette.accent.opacity(0.32), lineWidth: 1))
    }

    private func errorBanner(message: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: "xmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(Surface.danger)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Unable to Process File")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.sm)
            Button("Rescan") {
                model.rescanItem(id: item.id)
            }
            .buttonStyle(.bordered)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.dangerTint, in: shape)
        .overlay(shape.strokeBorder(Surface.danger.opacity(0.35), lineWidth: 1))
    }

    private var footerActionBar: some View {
        HStack(spacing: Space.sm) {
            Button(item.restoreButtonTitle, systemImage: "arrow.uturn.backward") {
                model.restoreOriginal(for: item.id)
            }
            .disabled(!item.canRestore)
            .help("Restore the file's original Matroska pixel-crop headers (⌥⌘Z)")

            Button("Rescan", systemImage: "viewfinder") {
                model.rescanItem(id: item.id)
            }
            .disabled(item.status == .scanning || item.isApplying)
            .help("Rescan this file with standard 3-interval detection (⌘R)")

            Button("Deep Scan", systemImage: "scope") {
                model.deepScanItem(id: item.id)
            }
            .disabled(item.status == .scanning || item.isApplying)
            .help("Deep scan this file across duration-scaled intervals (⌥⌘R)")

            Spacer(minLength: Space.sm)

            if item.isApplying {
                ProgressView()
                    .controlSize(.small)
                Text("Updating header…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Apply Crop", systemImage: "crop") {
                model.applyCrop(for: item.id)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!item.canApply)
            .help("Write Matroska pixel-crop headers losslessly in-place (⌘↩)")
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "Unknown length" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
