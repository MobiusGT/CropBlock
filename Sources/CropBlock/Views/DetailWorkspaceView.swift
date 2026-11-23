import SwiftUI
import CropBlockKit

struct DetailWorkspaceView: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    headerSummary
                        .gridProbe("fileHeader", area: "detail")

                    PreviewCanvasView(item: item, compactHeight: item.status == .variableAR)
                        .gridProbe("previewCanvas", area: "detail")

                    if item.status == .variableAR, let detection = item.detection {
                        variableARBanner(detection: detection)
                            .gridProbe("variableARBanner", area: "detail")
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

            StatusBadge(status: item.status)
        }
    }

    private func variableARBanner(detection: CropDetectionResult) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        let summary = detection.samples.map { sample -> String in
            if let rect = sample.detectedRect {
                return "\(sample.window.label): \(rect.width)×\(rect.height)"
            }
            return "\(sample.window.label): black"
        }.joined(separator: "  ·  ")

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

            Text("Sampled timestamps disagree on active video dimensions (common in IMAX releases). Crop Block computed the conservative union bounding box so wider scenes are not cut off. Inspect all sample frames above before applying.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)

            Toggle(
                "Allow crop despite variable aspect ratio",
                isOn: Binding(
                    get: { item.variableARConfirmed },
                    set: { model.setVariableARConfirmed($0, for: item.id) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.callout.weight(.medium))
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.warningTint, in: shape)
        .overlay(shape.strokeBorder(Surface.warning.opacity(0.4), lineWidth: 1))
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
            .help("Restore the file's original Matroska header properties (⌥⌘Z)")

            Button("Rescan", systemImage: "viewfinder") {
                model.rescanItem(id: item.id)
            }
            .disabled(item.status == .scanning || item.isApplying)
            .help("Rescan this file for black bars (⌘R)")

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
            .help("Write Matroska crop headers losslessly in-place (⌘↩)")
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
