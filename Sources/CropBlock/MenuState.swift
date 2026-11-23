import Combine
import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case detection
    case tools
    case appearance

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .detection: "Detection"
        case .tools: "Tools"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .detection: "viewfinder"
        case .tools: "wrench.and.screwdriver"
        case .appearance: "paintbrush"
        }
    }
}

enum SnapshotPage: String, CaseIterable {
    case empty
    case detected
    case framingJitter = "framing-jitter"
    case variableAR = "variable-ar"
    case deepScanned = "deep-scanned"
    case cropped
    case setup
    case compatibility
}

struct AppBanner: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case info
        case error

        var defaultAutoDismiss: Duration? {
            switch self {
            case .success, .info: .milliseconds(3500)
            case .error: nil
            }
        }

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .info: "info.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }
    }

    let id: UUID
    let message: String
    let kind: Kind

    init(id: UUID = UUID(), message: String, kind: Kind) {
        self.id = id
        self.message = message
        self.kind = kind
    }
}

/// Mirrors `@Observable` AppModel state into an `ObservableObject` so SwiftUI menu bar commands
/// enable and disable reliably on macOS.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()

    @Published var hasSelection = false
    @Published var hasPending = false
    @Published var isScanning = false
    @Published var canDeepScanSelected = false
    @Published var deepScanAllCount = 0
    @Published var canApplySelected = false
    @Published var canRestoreSelected = false
    @Published var restoreTitle = "Restore Original"
    @Published var cropAllReadyCount = 0
    @Published var isBatchApplying = false
    @Published var hasCompleted = false
    @Published var showsCropOverlay = true
    @Published var sampleCount = 0

    func sync(from model: AppModel) {
        let sel = model.selectedItem
        hasSelection = sel != nil
        hasPending = model.items.contains { $0.status == .pending }
        isScanning = model.isScanning
        canDeepScanSelected = sel != nil && sel?.status != .scanning && sel?.isApplying == false
        deepScanAllCount = model.deepScanAllCount
        canApplySelected = sel?.canApply ?? false
        canRestoreSelected = sel?.canRestore ?? false
        restoreTitle = sel?.restoreButtonTitle ?? "Restore Original"
        cropAllReadyCount = model.cropAllReadyCount
        isBatchApplying = model.isBatchApplying
        hasCompleted = model.items.contains { $0.status == .cropped || $0.status == .noBars }
        showsCropOverlay = model.showsCropOverlay
        sampleCount = sel?.previewSamples.count ?? 0
    }
}
