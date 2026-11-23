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
        if item.status != .scanning {
            Button("Scan Again", systemImage: "viewfinder") {
                model.rescanItem(id: item.id)
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
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(item.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.url.path)

                Spacer(minLength: Space.xs)

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
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.fileName), \(item.status.label), \(subtitleText)")
    }

    private var subtitleText: String {
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
