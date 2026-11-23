import Foundation
import Observation
import CropBlockKit

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
}

@Observable
final class AppModel {
    var settingsTab: SettingsTab = .general
    var statusMessage: String?

    init() {}
}
