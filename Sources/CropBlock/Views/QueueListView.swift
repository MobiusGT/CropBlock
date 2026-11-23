import SwiftUI
import CropBlockKit

struct QueueListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectionID) {
            ForEach(model.items) { item in
                QueueRowView(item: item)
                    .tag(item.id)
                    .contextMenu {
                        rowContextMenu(for: item)
                    }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            model.removeSelected()
        }
        .overlay {
            if model.items.isEmpty {
                ContentUnavailableView {
                    Label("No Files", systemImage: "film.stack")
                } description: {
                    Text("Queued MKV files appear here.")
                }
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(for item: QueueItem) -> some View {
        if item.status != .scanning && !item.isApplying {
            Button("Scan Again", systemImage: "viewfinder") {
                model.rescanItem(id: item.id)
            }
            Button("Deep Scan", systemImage: "scope") {
                model.deepScanItem(id: item.id)
            }
        }
        if item.canApply {
            Button("Apply Crop", systemImage: "crop") {
                model.applyCrop(for: item.id)
            }
        }
        if item.canRestore {
            Button(item.restoreButtonTitle, systemImage: "arrow.uturn.backward") {
                model.restoreOriginal(for: item.id)
            }
        }
        Divider()
        Button("Reveal in Finder", systemImage: "folder") {
            model.revealInFinder(id: item.id)
        }
        Button("Remove from Queue", systemImage: "minus.circle") {
            model.removeItem(id: item.id)
        }
    }
}

private struct QueueRowView: View {
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(item.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.url.path)

                Spacer(minLength: Space.xs)

                if item.shouldSuggestDeepScan && item.status == .detected {
                    Image(systemName: "scope")
                        .font(.caption)
                        .foregroundStyle(Palette.accentText)
                        .help("Inconsistent framing detected — Deep Scan recommended")
                        .accessibilityLabel("Deep Scan recommended")
                }

                StatusBadge(status: item.status)
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                if let parent = item.parentContext {
                    Label(parent, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(subtitleText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if item.isDeepScanned, item.status != .scanning {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(deepCompactTag)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.accentText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.fileName), \(item.status.label), \(subtitleText)")
    }

    private var deepCompactTag: String {
        guard let detection = item.detection else { return "Deep" }
        return detection.isFullVideoSinglePass ? "Full Scan" : "\(detection.samples.count)x Deep"
    }

    private var subtitleText: String {
        if case .scanning = item.status {
            return item.scanningDetailText
        }
        if let err = item.status.errorMessage {
            return err
        }
        return item.resolutionSummary
    }

    private var subtitleColor: Color {
        if case .error = item.status {
            return Surface.danger
        }
        return .secondary
    }
}
