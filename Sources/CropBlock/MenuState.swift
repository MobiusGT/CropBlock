import Combine
import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        }
    }
}

enum SnapshotPage: String, CaseIterable {
    case empty
    case detected
    case variableAR = "variable-ar"
    case cropped
    case setup
    case compatibility
}

/// Mirrors `@Observable` AppModel state into an `ObservableObject` so SwiftUI menu bar commands
/// enable and disable reliably on macOS.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()

    @Published var hasSelection = false
    @Published var hasPending = false
    @Published var isScanning = false
    @Published var canApplySelected = false
    @Published var canRestoreSelected = false
    @Published var restoreTitle = "Restore Original"
    @Published var hasCompleted = false
    @Published var showsCropOverlay = true
    @Published var sampleCount = 0

    func sync(from model: AppModel) {
        let sel = model.selectedItem
        hasSelection = sel != nil
        hasPending = model.items.contains { $0.status == .pending }
        isScanning = model.isScanning
        canApplySelected = sel?.canApply ?? false
        canRestoreSelected = sel?.canRestore ?? false
        restoreTitle = sel?.restoreButtonTitle ?? "Restore Original"
        hasCompleted = model.items.contains { $0.status == .cropped || $0.status == .noBars }
        showsCropOverlay = model.showsCropOverlay
        sampleCount = sel?.detection?.samples.count ?? 0
    }
}
