import AppKit
import SwiftUI
import CropBlockKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab(SettingsTab.general.title, systemImage: SettingsTab.general.symbol, value: SettingsTab.general) {
                GeneralSettingsTab()
                    .environment(model)
            }

            Tab(SettingsTab.detection.title, systemImage: SettingsTab.detection.symbol, value: SettingsTab.detection) {
                DetectionSettingsTab()
                    .environment(model)
            }

            Tab(SettingsTab.tools.title, systemImage: SettingsTab.tools.symbol, value: SettingsTab.tools) {
                ToolsSettingsTab()
                    .environment(model)
            }

            Tab(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.symbol, value: SettingsTab.appearance) {
                Form {
                    AppearanceSettings()
                }
                .formStyle(.grouped)
                .fitsContent()
            }
        }
        .frame(width: 520)
        .noInitialFocus()
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Queue") {
                Toggle("Automatically scan files when added", isOn: $model.detectionSettings.autoScanOnAdd)
            }

            Section("Restore History") {
                LabeledContent("Saved receipts") {
                    HStack(spacing: Space.md) {
                        Text("\(model.savedReceiptCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Clear Saved Receipts") {
                            model.clearAllReceipts()
                        }
                        .disabled(model.savedReceiptCount == 0)
                    }
                }
            }

            Section("About") {
                LabeledContent("Application", value: AppMetadata.displayName)
                LabeledContent("Repository") {
                    Link("github.com/MobiusGT/CropBlock", destination: AppMetadata.repositoryURL)
                }
                LabeledContent("Releases") {
                    Link("GitHub Releases", destination: AppMetadata.releasesURL)
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}

private struct DetectionSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let pcts = model.detectionSettings.samplePercentages

        Form {
            Section("Sampling Windows") {
                ForEach(0..<3, id: \.self) { idx in
                    let current = idx < pcts.count ? Int((pcts[idx] * 100).rounded()) : [20, 50, 80][idx]
                    LabeledContent("Sample \(idx + 1)") {
                        Stepper(
                            value: Binding(
                                get: { current },
                                set: { model.updateSamplePercentage(at: idx, percent: $0) }
                            ),
                            in: 1...99,
                            step: 5
                        ) {
                            Text("\(current)%")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                LabeledContent("Sample duration") {
                    Stepper(
                        value: Binding(
                            get: { Int(model.detectionSettings.sampleDurationSeconds.rounded()) },
                            set: { model.detectionSettings.sampleDurationSeconds = Double($0) }
                        ),
                        in: 1...60,
                        step: 1
                    ) {
                        Text("\(Int(model.detectionSettings.sampleDurationSeconds.rounded())) s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Crop Detection") {
                LabeledContent("Luma limit (cropdetect)") {
                    Stepper(
                        value: $model.detectionSettings.cropDetectLimit,
                        in: 0...255,
                        step: 2
                    ) {
                        Text("\(model.detectionSettings.cropDetectLimit)")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                LabeledContent("Minimum bar threshold") {
                    Stepper(
                        value: $model.detectionSettings.noiseFloorPixels,
                        in: 0...32,
                        step: 2
                    ) {
                        Text("\(model.detectionSettings.noiseFloorPixels) px")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                LabeledContent("Concurrent scans") {
                    Stepper(
                        value: $model.detectionSettings.maxConcurrentScans,
                        in: 1...4,
                        step: 1
                    ) {
                        Text("\(model.detectionSettings.maxConcurrentScans)")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset Detection Defaults") {
                        model.resetDetectionSettings()
                    }
                    .disabled(model.detectionSettings == .default)
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}

private struct ToolsSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        Form {
            Section("Command-Line Tools") {
                ForEach(ExternalTool.allCases) { tool in
                    toolRow(tool)
                }
            }

            Section("Homebrew") {
                LabeledContent("Install command") {
                    HStack(spacing: Space.sm) {
                        Text(AppMetadata.homebrewInstallCommand)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AppMetadata.homebrewInstallCommand, forType: .string)
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        }
                        .controlSize(.small)
                    }
                }

                HStack {
                    Spacer()
                    Button("Re-check Tools", systemImage: "arrow.clockwise") {
                        Task { await model.refreshTools(presentSheetIfMissing: false) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }

    private func toolRow(_ tool: ExternalTool) -> some View {
        let status = model.tools[tool]
        let hasCustom = !model.customToolPaths[tool].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(status.isAvailable ? Surface.success : Surface.danger)
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

                Spacer(minLength: Space.sm)

                if hasCustom {
                    Button("Clear") {
                        model.setCustomToolPath("", for: tool)
                    }
                    .controlSize(.small)
                    .help("Clear custom path and fall back to automatic discovery")
                }

                Button("Browse…") {
                    model.browseCustomTool(for: tool)
                }
                .controlSize(.small)
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
                    .foregroundStyle(Surface.danger)
            }
        }
        .padding(.vertical, Space.xs)
    }
}
