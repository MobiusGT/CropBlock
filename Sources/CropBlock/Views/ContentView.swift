import SwiftUI
import CropBlockKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    EmptyView()
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
            .overlay {
                ContentUnavailableView {
                    Label("No Files", systemImage: "film.stack")
                } description: {
                    Text("Queued MKV files appear here.")
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: Space.lg) {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Surface.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(Surface.hairline, style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
                    )
                    .overlay {
                        ContentUnavailableView {
                            Label("Drop MKV Files or Folders", systemImage: "crop")
                        } description: {
                            Text("Crop Block detects black bars and edits Matroska headers without re-encoding.")
                        } actions: {
                            Button("Add Files…", systemImage: "plus") {}
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .help("Add MKV files or folders to the queue (⌘O)")
                        }
                    }
                    .gridProbe("emptyDropZone", area: "detail")
            }
            .padding(Space.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gridArea("detail", inset: Space.margin)
            .navigationTitle("Queue")
            .navigationSubtitle("0 files")
            .toolbar {
                CompatToolbarFlexibleSpacer()
                ToolbarItem {
                    Button("Player Compatibility", systemImage: "info.circle") {}
                        .help("View player compatibility for Matroska crop headers")
                }
            }
        }
        .noInitialFocus()
    }
}
