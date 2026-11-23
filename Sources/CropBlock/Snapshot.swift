import AppKit
import IOKit.pwr_mgt
import SwiftUI
import CropBlockKit

enum Snapshot {
    static var isActive: Bool {
        !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty
    }

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        guard StoreLocation.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a path in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Snapshots" as CFString,
                &awake
            )
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            let wake = Process()
            wake.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            wake.arguments = ["-u", "-t", "2"]
            try? wake.run()
            try? await Task.sleep(for: .seconds(1.8))

            let realTools = model.tools

            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)

                for page in SnapshotPage.allCases where only?.contains(page.rawValue) ?? true {
                    configure(page: page, model: model, realTools: realTools)
                    let settleSeconds = page == .setup ? 1.1 : 0.7
                    try? await Task.sleep(for: .seconds(settleSeconds))

                    let mainWindow = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    let writeLayout = (page != .setup && page != .compatibility)
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png", window: mainWindow, writeLayout: writeLayout)

                    // Dismiss modal surfaces cleanly before next page
                    if model.showsToolSetupSheet {
                        model.showsToolSetupSheet = false
                        model.tools = realTools
                        try? await Task.sleep(for: .seconds(0.4))
                    }
                    if model.showsCompatibilityPopover {
                        model.showsCompatibilityPopover = false
                        try? await Task.sleep(for: .seconds(0.3))
                    }
                }
            }

            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(0.8))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.6))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings, writeLayout: false)
                    }
                }
            }

            print("SNAPSHOT done \(dir)")
            for window in NSApp.windows {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
            }
            NSApp.terminate(nil)
        }
    }

    private static func configure(page: SnapshotPage, model: AppModel, realTools: ResolvedTools) {
        model.showsToolSetupSheet = false
        model.showsCompatibilityPopover = false
        model.showsCropOverlay = true
        model.dismissBanner()
        model.tools = realTools

        switch page {
        case .empty:
            model.items = []
            model.selectionID = nil
        case .detected:
            if model.items.isEmpty { SeedData.populate(into: model) }
            model.selectionID = model.items.first { $0.status == .detected }?.id
        case .variableAR:
            if model.items.isEmpty { SeedData.populate(into: model) }
            model.selectionID = model.items.first { $0.status == .variableAR }?.id
        case .cropped:
            if model.items.isEmpty { SeedData.populate(into: model) }
            model.selectionID = model.items.first { $0.status == .cropped }?.id
        case .setup:
            if model.items.isEmpty { SeedData.populate(into: model) }
            model.selectionID = model.items.first { $0.status == .detected }?.id
            model.tools = SeedData.mockPartiallyMissingTools()
            model.showsToolSetupSheet = true
        case .compatibility:
            if model.items.isEmpty { SeedData.populate(into: model) }
            model.selectionID = model.items.first { $0.status == .detected }?.id
            model.showsCompatibilityPopover = true
        }
    }

    private static func capture(to path: String, window: NSWindow? = nil, writeLayout: Bool = true) {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if writeLayout {
            let size = window.contentView?.bounds.size ?? .zero
            GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        }
        try? FileManager.default.removeItem(atPath: path)
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission)")
        }
    }
}
