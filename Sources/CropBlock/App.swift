import AppKit
import SwiftUI
import CropBlockKit

@main
struct CropBlockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @ObservedObject private var menu = MenuState.shared
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        Window(AppMetadata.displayName, id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 860, minHeight: 580)
                .task {
                    await model.startupCheck()
                    SelfTest.runIfRequested(model: model)
                    Snapshot.runIfRequested(model: model, openSettings: openSettings)
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()

            CommandGroup(after: .appSettings) {
                Button("Tool Setup…") {
                    model.showsToolSetupSheet = true
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Add Files…") {
                    model.openFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Queue") {
                Button("Scan Selected") {
                    if let id = model.selectionID { model.rescanItem(id: id) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!menu.hasSelection)

                Button("Scan All Pending") {
                    model.scanAllPending()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!menu.hasPending || menu.isScanning)

                Button("Stop Scanning") {
                    model.stopScanning()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!menu.isScanning)

                Divider()

                Button("Clear Completed") {
                    model.clearCompleted()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(!menu.hasCompleted)
            }

            CommandMenu("Crop") {
                Button("Apply Crop") {
                    if let id = model.selectionID { model.applyCrop(for: id) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!menu.canApplySelected)

                Button(menu.restoreTitle) {
                    if let id = model.selectionID { model.restoreOriginal(for: id) }
                }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(!menu.canRestoreSelected)
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Button(menu.showsCropOverlay ? "Hide Crop Overlay" : "Show Crop Overlay") {
                    model.showsCropOverlay.toggle()
                }
                .disabled(!menu.hasSelection)

                Menu("Sample Frame") {
                    ForEach(0..<3, id: \.self) { idx in
                        Button("Sample \(idx + 1)") {
                            if let id = model.selectionID { model.selectSample(idx, for: id) }
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
                        .disabled(idx >= menu.sampleCount)
                    }
                }
            }

            CommandGroup(replacing: .help) {
                Button("Player Compatibility") {
                    model.showsCompatibilityPopover.toggle()
                }
                Divider()
                Link("Crop Block on GitHub", destination: AppMetadata.repositoryURL)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Handles MKV files and folders dropped onto the Dock icon or opened via Finder "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.addURLs(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.cleanupPreviewCache()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where local edit receipts live: ~/Library/Application Support/CropBlock/
/// Overridden via APP_STORE during tests and snapshots so real user data is never touched.
enum StoreLocation {
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var directoryURL: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let dir = URL.applicationSupportDirectory.appending(path: AppMetadata.executableName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
