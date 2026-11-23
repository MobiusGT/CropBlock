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
            check("Bundle identifier configured", AppMetadata.bundleIdentifier == "io.github.mobiusgt.cropblock")

            let symbols = [
                "crop", "plus", "info.circle", "film.stack", "clock",
                "checkmark.circle", "exclamationmark.triangle.fill",
                "checkmark.seal.fill", "xmark.octagon.fill", "gearshape", "paintbrush",
            ]
            for name in symbols {
                check("SF Symbol '\(name)' exists", NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
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
