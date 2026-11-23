import SwiftUI
import UniformTypeIdentifiers
import CropBlockKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            QueueListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 312, max: 400)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Add Files…", systemImage: "plus") {
                            model.openFilePanel()
                        }
                        .help("Add MKV files or folders to the queue (⌘O)")

                        if model.isScanning {
                            Button("Stop Scanning", systemImage: "stop.fill") {
                                model.stopScanning()
                            }
                            .help("Stop scanning queued files (⌘.)")
                        } else {
                            Button("Scan All Pending", systemImage: "viewfinder") {
                                model.scanAllPending()
                            }
                            .disabled(!model.items.contains { $0.status == .pending })
                            .help("Scan all pending files for black bars (⇧⌘R)")
                        }
                    }
                }
        } detail: {
            Group {
                if let selected = model.selectedItem {
                    DetailWorkspaceView(item: selected)
                } else {
                    emptyDetailView
                }
            }
            .overlay(alignment: .top) {
                if let message = model.bannerMessage {
                    bannerView(message: message)
                        .padding(Space.md)
                }
            }
            .navigationTitle("Queue")
            .navigationSubtitle(model.queueSubtitle)
            .toolbar {
                CompatToolbarFlexibleSpacer()

                if !model.tools.allAvailable {
                    ToolbarItem {
                        Button("Tool Setup…", systemImage: "wrench.and.screwdriver") {
                            model.showsToolSetupSheet = true
                        }
                        .tint(Surface.warning)
                        .help("Open Tool Setup to install missing command-line tools")
                    }
                    CompatToolbarFixedSpacer()
                }

                ToolbarItem {
                    Button("Player Compatibility", systemImage: "info.circle") {
                        model.showsCompatibilityPopover.toggle()
                    }
                    .help("View player compatibility for Matroska crop headers")
                    .popover(isPresented: $model.showsCompatibilityPopover, arrowEdge: .bottom) {
                        CompatibilityPopover()
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
        .onKeyPress(.space) {
            guard model.selectedItem?.inspection != nil else { return .ignored }
            withAnimation(Motion.quick(reduceMotion: reduceMotion)) {
                model.showsCropOverlay.toggle()
            }
            return .handled
        }
        .sheet(isPresented: $model.showsToolSetupSheet) {
            ToolOnboardingSheet()
                .environment(model)
        }
        .noInitialFocus()
    }

    private var emptyDetailView: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: Space.lg) {
            shape
                .fill(model.isDropTargeted ? Palette.accent.opacity(0.08) : Surface.card)
                .overlay(
                    shape.strokeBorder(
                        model.isDropTargeted ? Palette.accent : Surface.hairline,
                        style: StrokeStyle(lineWidth: model.isDropTargeted ? 2 : 1, dash: [8, 6])
                    )
                )
                .overlay {
                    if model.items.isEmpty {
                        ContentUnavailableView {
                            Label("Drop MKV Files or Folders", systemImage: "crop")
                        } description: {
                            Text("Crop Block detects black bars and edits Matroska headers without re-encoding.")
                        } actions: {
                            Button("Add Files…", systemImage: "plus") {
                                model.openFilePanel()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .help("Add MKV files or folders to the queue (⌘O)")
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Select a File", systemImage: "sidebar.leading")
                        } description: {
                            Text("Choose an MKV file from the queue to preview its crop.")
                        }
                    }
                }
                .gridProbe("emptyDropZone", area: "detail")
        }
        .padding(Space.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gridArea("detail", inset: Space.margin)
    }

    private func bannerView(message: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
            Spacer(minLength: Space.sm)
            Button("Dismiss", systemImage: "xmark") {
                model.bannerMessage = nil
            }
            .buttonStyle(.plain)
            .labelStyle(.iconOnly)
            .help("Dismiss message")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .floatingGlassPill()
        .frame(maxWidth: 480)
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matching.isEmpty else { return false }

        Task {
            var collected: [URL] = []
            for provider in matching {
                if let url = await loadFileURL(from: provider) {
                    collected.append(url)
                }
            }
            model.addURLs(collected)
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
