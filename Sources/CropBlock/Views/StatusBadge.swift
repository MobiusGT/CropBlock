import SwiftUI

/// Accessible status badge that always pairs an SF Symbol (or spinner) with a text label.
struct StatusBadge: View {
    let status: QueueItemStatus

    var body: some View {
        HStack(spacing: Space.xs) {
            if case .scanning = status {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.75)
            } else {
                Image(systemName: status.symbol)
                    .font(.caption.weight(.medium))
            }
            Text(status.label)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 2)
        .background(background, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.label)")
    }

    private var foreground: Color {
        switch status {
        case .pending, .scanning: .secondary
        case .detected: Palette.accentText
        case .noBars: .secondary
        case .variableAR: Surface.warning
        case .cropped: Surface.success
        case .error: Surface.danger
        }
    }

    private var background: Color {
        switch status {
        case .pending, .scanning, .noBars: Surface.card
        case .detected: Palette.accent.opacity(0.14)
        case .variableAR: Surface.warningTint
        case .cropped: Surface.success.opacity(0.14)
        case .error: Surface.dangerTint
        }
    }
}
