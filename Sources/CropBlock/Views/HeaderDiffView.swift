import SwiftUI
import CropBlockKit

/// Aligned Matroska `track:v1` before-and-after diff table for `pixel-crop-*` properties.
/// Display dimensions (`display-width`, `display-height`, `display-unit`) are never modified.
struct HeaderDiffView: View {
    let inspection: VideoInspection
    let plan: CropApplyPlan
    let isCropped: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text("Matroska Header Changes (track:v1)")
                    .font(.headline)

                Spacer(minLength: Space.sm)

                if !inspection.sar.isSquare {
                    Label("Anamorphic SAR \(inspection.sar.formatted)", systemImage: "aspectratio")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(Palette.accent.opacity(0.14), in: Capsule())
                }

                Text("Active AR \(inspection.fullFrameDisplayDimensions.formattedAspectRatio) → \(plan.displayDimensions.formattedAspectRatio)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .gridProbe("diffHeader", area: "diffCard")

            Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.xs) {
                GridRow {
                    Text("Property")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("")
                    Text(isCropped ? "Applied" : "Target")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }

                Divider()
                    .gridCellUnsizedAxes(.horizontal)

                ForEach(plan.changes) { change in
                    GridRow {
                        Text(change.property)
                            .font(.callout.monospaced())
                            .foregroundStyle(.primary)
                        Text(change.before)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(change.after)
                            .font(.callout.weight(change.changed ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(valueColor(changed: change.changed))
                    }
                }
            }
            .gridProbe("diffGrid", area: "diffCard")

            Text("Only pixel-crop-* tags are edited; display-width, display-height, and display-unit remain untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridProbe("diffNote", area: "diffCard")
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.card, in: shape)
        .overlay(shape.strokeBorder(Surface.hairline, lineWidth: 1))
        .gridArea("diffCard", inset: Space.lg)
    }

    private func valueColor(changed: Bool) -> Color {
        if isCropped {
            return Surface.success
        }
        return changed ? Palette.accentText : .secondary
    }
}
