import SwiftUI
import CropBlockKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab(SettingsTab.general.title, systemImage: SettingsTab.general.symbol, value: SettingsTab.general) {
                Form {
                    Section("About") {
                        LabeledContent("Application", value: AppMetadata.displayName)
                        LabeledContent("Source Code") {
                            Link("github.com/MobiusGT/CropBlock", destination: AppMetadata.repositoryURL)
                        }
                    }
                }
                .formStyle(.grouped)
                .fitsContent()
            }

            Tab(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.symbol, value: SettingsTab.appearance) {
                Form {
                    AppearanceSettings()
                }
                .formStyle(.grouped)
                .fitsContent()
            }
        }
        .frame(width: 480)
        .noInitialFocus()
    }
}
