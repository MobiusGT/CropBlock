import AppKit
import SwiftUI
import CropBlockKit

/// SAR-corrected sample frame canvas with live dimmed crop bars, crisp crop boundary,
/// dimension/offset HUD pill, overlay visibility toggle, and 20% / 50% / 80% sample switcher.
struct PreviewCanvasView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: QueueItem
    var compactHeight: Bool = false

    private var canvasHeight: CGFloat {
        compactHeight ? 248 : 304
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        ZStack {
            Surface.previewCanvas

            if let inspection = item.inspection {
                previewContent(inspection: inspection)
            } else if case .scanning = item.status {
                VStack(spacing: Space.sm) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Scanning black bars and extracting preview…")
                        .font(.callout)
                        .foregroundStyle(Surface.hudForeground.opacity(0.85))
                }
            } else {
                VStack(spacing: Space.sm) {
                    Image(systemName: "film")
                        .font(.title)
                        .foregroundStyle(Surface.hudForeground.opacity(0.6))
                    Text("Ready to Scan")
                        .font(.headline)
                        .foregroundStyle(Surface.hudForeground)
                    Button("Scan Now", systemImage: "viewfinder") {
                        model.rescanItem(id: item.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: canvasHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Surface.hairline, lineWidth: 1))
        .overlay(alignment: .bottom) {
            if let inspection = item.inspection {
                bottomHUD(inspection: inspection)
                    .padding(Space.md)
            }
        }
    }

    @ViewBuilder
    private func previewContent(inspection: VideoInspection) -> some View {
        let insets = item.activeInsets
        let displayAspect = max(0.2, inspection.fullFrameDisplayDimensions.aspectRatio)
        let boundaryColor = (item.status == .variableAR && !item.variableARConfirmed)
            ? Surface.warning
            : Palette.accent

        GeometryReader { geo in
            let container = geo.size
            let fitted = fitSize(aspectRatio: displayAspect, inside: CGSize(
                width: max(1, container.width - Space.lg * 2),
                height: max(1, container.height - Space.xxl * 2 - Space.lg)
            ))

            ZStack {
                // SAR-corrected frame image (or clean dark fallback)
                Group {
                    if let path = item.currentSample?.previewImagePath,
                       let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Rectangle()
                            .fill(Surface.previewCanvas)
                            .overlay {
                                VStack(spacing: Space.xs) {
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundStyle(Surface.hudForeground.opacity(0.4))
                                    Text("Preview frame unavailable")
                                        .font(.caption)
                                        .foregroundStyle(Surface.hudForeground.opacity(0.55))
                                }
                            }
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .overlay {
                    if model.showsCropOverlay && !insets.isZero {
                        CropOverlayCanvas(
                            frameWidth: CGFloat(inspection.storedWidth),
                            frameHeight: CGFloat(inspection.storedHeight),
                            insets: insets,
                            boundaryColor: boundaryColor
                        )
                        .animation(Motion.quick(reduceMotion: reduceMotion), value: insets)
                    }
                }
                .overlay(
                    Rectangle()
                        .strokeBorder(Surface.hudForeground.opacity(0.14), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, Space.lg)
        }
    }

    private func bottomHUD(inspection: VideoInspection) -> some View {
        let insets = item.activeInsets
        let targetDisplay = CropCalculator.displayDimensions(
            storedWidth: inspection.storedWidth,
            storedHeight: inspection.storedHeight,
            insets: insets,
            sar: inspection.sar
        )
        let samples = item.detection?.samples ?? []

        return HStack(spacing: Space.sm) {
            // Left pill: resolution + crop offsets
            HStack(spacing: Space.sm) {
                if insets.isZero {
                    Label("No Black Bars Detected", systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Surface.hudForeground)
                } else {
                    Text("\(inspection.formattedStoredResolution) → \(targetDisplay.formattedDimensions)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Surface.hudForeground)
                    Text("(\(targetDisplay.formattedAspectRatio))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Surface.hudForeground.opacity(0.8))
                    Divider()
                        .frame(height: Space.md)
                        .overlay(Surface.hudForeground.opacity(0.3))
                    Text(insets.summary)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Surface.hudForeground.opacity(0.9))
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .background(Surface.hudPill, in: Capsule())

            Spacer(minLength: Space.sm)

            // Sample timestamp switcher (20% | 50% | 80%)
            if samples.count > 1 {
                HStack(spacing: 2) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { idx, sample in
                        let selected = idx == min(item.selectedSampleIndex, samples.count - 1)
                        Button(sample.window.label) {
                            model.selectSample(idx, for: item.id)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Palette.onAccent : Surface.hudForeground.opacity(0.85))
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(selected ? Palette.accent : .clear, in: Capsule())
                        .help("Show sample frame at \(sample.window.label) (⌘\(idx + 1))")
                    }
                }
                .padding(2)
                .background(Surface.hudPill, in: Capsule())
            }

            // Overlay toggle button
            if !insets.isZero {
                Button {
                    withAnimation(Motion.quick(reduceMotion: reduceMotion)) {
                        model.showsCropOverlay.toggle()
                    }
                } label: {
                    Label(
                        model.showsCropOverlay ? "Hide Overlay" : "Show Overlay",
                        systemImage: model.showsCropOverlay ? "eye.slash" : "eye"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Surface.hudForeground)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
                    .background(Surface.hudPill, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle crop overlay visibility (Space)")
            }
        }
    }

    private func fitSize(aspectRatio: Double, inside bounds: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let containerRatio = bounds.width / bounds.height
        if containerRatio > aspectRatio {
            let h = bounds.height
            return CGSize(width: (h * aspectRatio).rounded(), height: h.rounded())
        } else {
            let w = bounds.width
            return CGSize(width: w.rounded(), height: (w / aspectRatio).rounded())
        }
    }
}

/// Draws dimmed crop bars, crisp crop boundary, and corner ticks using Canvas (zero `.offset` / `.position`).
private struct CropOverlayCanvas: View {
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let insets: CropInsets
    let boundaryColor: Color

    var body: some View {
        Canvas { context, size in
            guard frameWidth > 0, frameHeight > 0 else { return }
            let left = (CGFloat(insets.left) / frameWidth) * size.width
            let right = (CGFloat(insets.right) / frameWidth) * size.width
            let top = (CGFloat(insets.top) / frameHeight) * size.height
            let bottom = (CGFloat(insets.bottom) / frameHeight) * size.height

            let activeRect = CGRect(
                x: left,
                y: top,
                width: max(0, size.width - left - right),
                height: max(0, size.height - top - bottom)
            )

            // Dimmed letterbox & pillarbox regions
            var maskPath = Path()
            maskPath.addRect(CGRect(origin: .zero, size: size))
            maskPath.addRect(activeRect)
            context.fill(maskPath, with: .color(Surface.cropScrim), style: FillStyle(eoFill: true))

            // Crisp active crop boundary
            context.stroke(Path(activeRect.insetBy(dx: 1, dy: 1)), with: .color(boundaryColor), lineWidth: 2)

            // Corner ticks for surgical precision
            let tick = min(16, min(activeRect.width, activeRect.height) * 0.2)
            var corners = Path()
            // Top-left
            corners.move(to: CGPoint(x: activeRect.minX, y: activeRect.minY + tick))
            corners.addLine(to: CGPoint(x: activeRect.minX, y: activeRect.minY))
            corners.addLine(to: CGPoint(x: activeRect.minX + tick, y: activeRect.minY))
            // Top-right
            corners.move(to: CGPoint(x: activeRect.maxX - tick, y: activeRect.minY))
            corners.addLine(to: CGPoint(x: activeRect.maxX, y: activeRect.minY))
            corners.addLine(to: CGPoint(x: activeRect.maxX, y: activeRect.minY + tick))
            // Bottom-left
            corners.move(to: CGPoint(x: activeRect.minX, y: activeRect.maxY - tick))
            corners.addLine(to: CGPoint(x: activeRect.minX, y: activeRect.maxY))
            corners.addLine(to: CGPoint(x: activeRect.minX + tick, y: activeRect.maxY))
            // Bottom-right
            corners.move(to: CGPoint(x: activeRect.maxX - tick, y: activeRect.maxY))
            corners.addLine(to: CGPoint(x: activeRect.maxX, y: activeRect.maxY))
            corners.addLine(to: CGPoint(x: activeRect.maxX, y: activeRect.maxY - tick))
            context.stroke(corners, with: .color(Surface.hudForeground), lineWidth: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
