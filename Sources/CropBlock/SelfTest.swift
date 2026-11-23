import AppKit
import CropBlockKit

@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard StoreLocation.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a path in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.4))

            // 1. Metadata & SF Symbols audit
            check("Bundle identifier matches io.github.mobiusgt.cropblock", AppMetadata.bundleIdentifier == "io.github.mobiusgt.cropblock")
            let symbols = [
                "crop", "plus", "info.circle", "film.stack", "clock", "hourglass",
                "checkmark.circle", "checkmark.circle.fill", "exclamationmark.triangle.fill",
                "checkmark.seal.fill", "xmark.octagon.fill", "xmark.circle.fill",
                "gearshape", "paintbrush", "viewfinder", "stop.fill", "arrow.uturn.backward",
                "folder", "minus.circle", "eye", "eye.slash", "aspectratio", "arrow.right",
                "wrench.and.screwdriver", "arrow.clockwise", "doc.on.doc", "play.rectangle",
                "info.circle.fill", "xmark", "scope",
            ]
            for name in symbols {
                check("SF Symbol '\(name)' exists", NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
            }

            // 2. Seed data + Variable AR guard + Deep Scan suggestion/batch counts + Manual offsets
            SeedData.populate(into: model)
            check("Seed queue loaded 8 files", model.items.count == 8)

            if let film = model.items.first(where: { $0.status == .detected && $0.shouldSuggestDeepScan }) {
                check("Film transfer jitter item suggests Deep Scan", film.shouldSuggestDeepScan)
            } else {
                check("Film transfer jitter seed item present", false)
            }

            if let deep = model.items.first(where: { $0.isDeepScanned }) {
                check("Deep Scanned item shows 15-sample badge and 5 preview frames", deep.deepScanBadgeLabel == "Deep Scanned · 15 samples" && deep.previewSamples.count == 5)
                check("Deep Scanned item does not suggest Deep Scan again", !deep.shouldSuggestDeepScan)
            } else {
                check("Deep Scanned seed item present", false)
            }

            if let dune = model.items.first(where: { $0.status == .detected && !$0.shouldSuggestDeepScan && !$0.isDeepScanned }) {
                let originalTop = dune.activeInsets.top
                model.setInset(.top, value: originalTop + 2, for: dune.id)
                let adjusted = model.items.first { $0.id == dune.id }
                check("Manual top +2 adjusts active inset", adjusted?.activeInsets.top == originalTop + 2 && adjusted?.isManuallyAdjusted == true)
                model.resetManualInsets(for: dune.id)
                let reset = model.items.first { $0.id == dune.id }
                check("Reset restores detected offsets", reset?.activeInsets.top == originalTop && reset?.isManuallyAdjusted == false)
            }

            // Deep Scan All skips already-Deep-Scanned (Lawrence) and already-Cropped (Arrival): 8 - 2 = 6 eligible
            check("Deep Scan All skips already-Deep-Scanned and Cropped files (6 of 8)", model.deepScanAllCount == 6)

            if let imax = model.items.first(where: { $0.status == .variableAR }) {
                // Crop All ready: Dune + Blade Runner + Lawrence = 3 (skips unconfirmed Variable AR, Cropped, No Bars, Pending, Error)
                check("Crop All ready skips unconfirmed Variable AR (3 ready)", model.cropAllReadyCount == 3)
                check("Variable AR item blocks Apply until confirmed", !imax.canApply)
                model.setVariableARConfirmed(true, for: imax.id)
                let confirmed = model.items.first { $0.id == imax.id }
                check("Confirming Variable AR enables Apply", confirmed?.canApply == true)
                check("Crop All ready includes confirmed Variable AR (now 4 ready)", model.cropAllReadyCount == 4)

                model.selectSample(0, for: imax.id)
                check("Sample switcher selects index 0", model.items.first { $0.id == imax.id }?.selectedSampleIndex == 0)
            } else {
                check("Variable AR seed item present", false)
            }

            // 3. Remove selected advances selection to next row
            let firstID = model.items[0].id
            let secondID = model.items[1].id
            model.selectionID = firstID
            model.removeSelected()
            check("Remove selected deletes row and advances selection", model.items.count == 7 && model.selectionID == secondID)

            // 4. Settings validation & reset check
            model.updateSamplePercentage(at: 0, percent: 15)
            check("Detection settings update sample percentage", abs(model.detectionSettings.samplePercentages[0] - 0.15) < 0.001)
            model.resetDetectionSettings()
            check("Reset restores default detection settings", model.detectionSettings == .default)

            // 5. Auto-dismiss toast timer, reset on replacement, early dismiss, and persistent error check
            check("Success toast defaults to 3.5s auto-dismiss", AppBanner.Kind.success.defaultAutoDismiss == .milliseconds(3500))
            check("Error banner has no auto-dismiss", AppBanner.Kind.error.defaultAutoDismiss == nil)

            model.showBanner("First toast", kind: .success, autoDismissAfter: .milliseconds(160))
            check("Success toast appears immediately", model.banner?.message == "First toast")
            try? await Task.sleep(for: .milliseconds(100))
            // Replace before first timer fires -> must cancel first timer and start fresh 180ms countdown
            model.showBanner("Second toast", kind: .success, autoDismissAfter: .milliseconds(180))
            try? await Task.sleep(for: .milliseconds(100))
            check("Replaced toast is NOT dismissed prematurely by cancelled first timer", model.banner?.message == "Second toast")
            try? await Task.sleep(for: .milliseconds(140))
            check("Replaced toast auto-dismisses cleanly after full reset duration", model.banner == nil)

            model.showBanner("Persistent failure", kind: .error, autoDismissAfter: .milliseconds(60))
            try? await Task.sleep(for: .milliseconds(120))
            check("Error banner remains persistent past timeout", model.banner?.message == "Persistent failure")
            model.dismissBanner()
            check("Manual dismiss clears error banner immediately", model.banner == nil)

            // 6. Menu bar audit (verify required menus and commands exist)
            let menuTitles = NSApp.mainMenu?.items.map(\.title) ?? []
            check("Main menu has Queue menu", menuTitles.contains("Queue"))
            check("Main menu has Crop menu", menuTitles.contains("Crop"))

            // 5. Live end-to-end AppModel scan -> apply -> restore on real temp MKV (when tools installed)
            if let ffmpeg = model.tools.ffmpegURL, model.tools.allAvailable {
                let work = FileManager.default.temporaryDirectory.appending(path: "cb-selftest-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let mkv = work.appending(path: "test_letterbox.mkv")
                let gen = try? await ProcessRunner.run(executable: ffmpeg, arguments: [
                    "-hide_banner", "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", "color=c=0x2255AA:s=320x120:d=3,pad=320:180:0:30:black",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", mkv.path,
                ])
                if gen?.terminationStatus == 0, let mkvpropedit = model.tools.mkvpropeditURL {
                    // Stamp explicit display dimensions so self-test proves Crop Block leaves them untouched
                    _ = try? await ProcessRunner.run(executable: mkvpropedit, arguments: [
                        mkv.path, "--edit", "track:v1",
                        "--set", "display-unit=0",
                        "--set", "display-width=320",
                        "--set", "display-height=180",
                    ])
                    let beforeHeader = try? MatroskaHeaderReader.readVideoHeader(at: mkv)

                    model.items = []
                    model.selectionID = nil
                    model.detectionSettings = DetectionSettings(samplePercentages: [0.5], sampleDurationSeconds: 1, cropDetectLimit: 24)
                    model.addURLs([mkv], autoScan: true)

                    // Wait for background scan to finish (max 10s)
                    for _ in 0..<50 {
                        if let item = model.items.first, item.status != .pending && item.status != .scanning { break }
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                    let scanned = model.items.first
                    check("Background scan detects bars on real MKV", scanned?.status == .detected)
                    check("Detected insets equal T=30 B=30", scanned?.activeInsets == CropInsets(left: 0, right: 0, top: 30, bottom: 30))

                    if let id = scanned?.id {
                        // Also verify per-file Deep Scan runs cleanly on the live MKV
                        model.deepScanItem(id: id)
                        for _ in 0..<50 {
                            if let item = model.items.first, item.status != .pending && item.status != .scanning { break }
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                        check("Live per-file Deep Scan marks file Deep Scanned", model.items.first?.isDeepScanned == true && model.items.first?.activeInsets == CropInsets(left: 0, right: 0, top: 30, bottom: 30))

                        model.applyCrop(for: id)
                        for _ in 0..<25 {
                            if model.items.first?.isApplying == false && model.items.first?.status == .cropped { break }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        let afterApply = try? MatroskaHeaderReader.readVideoHeader(at: mkv)
                        check("Apply Crop transitions status to Cropped with receipt", model.items.first?.status == .cropped && model.items.first?.receipt != nil)
                        check(
                            "Apply Crop leaves display-width/height/unit untouched",
                            afterApply?.displayWidth == beforeHeader?.displayWidth
                                && afterApply?.displayHeight == beforeHeader?.displayHeight
                                && afterApply?.displayUnit == beforeHeader?.displayUnit
                        )

                        model.restoreOriginal(for: id)
                        for _ in 0..<25 {
                            if model.items.first?.isApplying == false && model.items.first?.status == .detected { break }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        let afterRestore = try? MatroskaHeaderReader.readVideoHeader(at: mkv)
                        check("Restore Original reverts status and clears receipt", model.items.first?.status == .detected && model.items.first?.receipt == nil)
                        check(
                            "Restore Original leaves display-width/height/unit untouched",
                            afterRestore?.displayWidth == beforeHeader?.displayWidth
                                && afterRestore?.displayHeight == beforeHeader?.displayHeight
                                && afterRestore?.displayUnit == beforeHeader?.displayUnit
                        )
                    }
                }
                try? FileManager.default.removeItem(at: work)
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        NSApp.terminate(nil)
    }
}
