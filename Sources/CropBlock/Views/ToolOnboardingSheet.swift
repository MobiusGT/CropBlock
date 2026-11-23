import AppKit
import SwiftUI
import CropBlockKit

/// Friendly, non-blocking onboarding sheet shown when `ffmpeg`, `ffprobe`, or `mkvpropedit` is missing.
struct ToolOnboardingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copiedCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Tool Setup")
                    .font(.title2.weight(.semibold))
                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Space.sm) {
                ForEach(ExternalTool.allCases) { tool in
                    toolRow(for: tool)
                }
            }

            homebrewBox

            HStack(spacing: Space.sm) {
                Button("Re-check Tools", systemImage: "arrow.clockwise") {
                    Task { await model.refreshTools(presentSheetIfMissing: false) }
                }
                .help("Scan for installed command-line tools again")

                Spacer(minLength: Space.sm)

                if model.tools.allAvailable {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue Anyway") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 520)
        .noInitialFocus()
    }

    private var headerSubtitle: String {
        if model.tools.allAvailable {
            return "All required command-line tools were found and are ready to use."
        }
        return "Crop Block uses ffmpeg, ffprobe, and mkvpropedit locally on your Mac. Install missing tools via Homebrew or select existing binaries below."
    }

    private func toolRow(for tool: ExternalTool) -> some View {
        let status = model.tools[tool]
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)

        return HStack(alignment: .center, spacing: Space.md) {
            Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(status.isAvailable ? Surface.success : Surface.danger)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(tool.displayName)
                        .font(.headline.monospaced())

                    if let source = status.source {
                        Text(source.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.accentText)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 2)
                            .background(Palette.accent.opacity(0.14), in: Capsule())
                    } else {
                        Text("Not Found")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Surface.danger)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 2)
                            .background(Surface.dangerTint, in: Capsule())
                    }

                    if let version = status.version {
                        Text(version)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                switch status {
                case .found(let url, _, _):
                    Text(url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                case .missing(let reason):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Space.sm)

            Button("Browse…") {
                model.browseCustomTool(for: tool)
            }
            .controlSize(.small)
            .help("Choose a custom binary for \(tool.displayName)")
        }
        .padding(Space.md)
        .background(Surface.card, in: shape)
        .overlay(shape.strokeBorder(Surface.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.displayName), \(status.isAvailable ? "available" : "not found")")
    }

    private var homebrewBox: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        return VStack(alignment: .leading, spacing: Space.sm) {
            Text("Install via Homebrew")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: Space.sm) {
                Text(AppMetadata.homebrewInstallCommand)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                Spacer(minLength: Space.sm)
                Button(copiedCommand ? "Copied" : "Copy Command", systemImage: copiedCommand ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AppMetadata.homebrewInstallCommand, forType: .string)
                    copiedCommand = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedCommand = false
                    }
                }
                .controlSize(.small)
            }
            .padding(Space.md)
            .background(Surface.card, in: shape)
            .overlay(shape.strokeBorder(Surface.hairline, lineWidth: 1))
        }
    }
}
