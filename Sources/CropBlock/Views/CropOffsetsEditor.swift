import SwiftUI
import CropBlockKit

enum CropEdge: String, CaseIterable, Identifiable {
    case top = "Top"
    case bottom = "Bottom"
    case left = "Left"
    case right = "Right"

    var id: String { rawValue }
}

/// Compact 4-column even-pixel (`±2 px`) offset adjuster with live preview/diff feedback and 1-click Reset.
struct CropOffsetsEditor: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem
    let inspection: VideoInspection

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text("Crop Offsets (px)")
                    .font(.headline)

                if item.isManuallyAdjusted {
                    Text("Adjusted")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(Palette.accent.opacity(0.14), in: Capsule())
                }

                Spacer(minLength: Space.sm)

                if item.isManuallyAdjusted {
                    Button("Reset") {
                        model.resetManualInsets(for: item.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reset crop offsets to automatically detected values")
                } else {
                    Text("Even pixels (±2)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .gridProbe("offsetsHeader", area: "offsetsCard")

            HStack(spacing: Space.md) {
                ForEach(CropEdge.allCases) { edge in
                    edgeControl(for: edge)
                }
            }
            .gridProbe("offsetsRow", area: "offsetsCard")
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.card, in: shape)
        .overlay(shape.strokeBorder(Surface.hairline, lineWidth: 1))
        .gridArea("offsetsCard", inset: Space.lg)
    }

    private func edgeControl(for edge: CropEdge) -> some View {
        let binding = Binding<Int>(
            get: { value(for: edge) },
            set: { newValue in
                model.setInset(edge, value: newValue, for: item.id)
            }
        )
        let maxBound = maxEdgeValue(for: edge)

        return HStack(spacing: Space.xs) {
            Text(edge.rawValue)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .leading)

            TextField(edge.rawValue, value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .disabled(item.isApplying || item.status == .scanning)
                .accessibilityLabel("\(edge.rawValue) crop offset in pixels")

            Stepper(
                value: binding,
                in: 0...maxBound,
                step: 2
            ) {
                EmptyView()
            }
            .labelsHidden()
            .controlSize(.small)
            .disabled(item.isApplying || item.status == .scanning)
            .help("Adjust \(edge.rawValue.lowercased()) crop offset by 2 pixels")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(for edge: CropEdge) -> Int {
        let insets = item.activeInsets
        switch edge {
        case .top: return insets.top
        case .bottom: return insets.bottom
        case .left: return insets.left
        case .right: return insets.right
        }
    }

    private func maxEdgeValue(for edge: CropEdge) -> Int {
        let minActive = 16
        switch edge {
        case .top, .bottom: return max(0, inspection.storedHeight - minActive)
        case .left, .right: return max(0, inspection.storedWidth - minActive)
        }
    }
}
