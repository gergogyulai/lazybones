import SwiftUI

struct HomeScreenSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPane(page: .homeScreen) {
            Section {
                Picker("Apps per row", selection: $model.settings.columns) {
                    ForEach(3...7, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Focused app size", selection: $model.settings.focusSize) {
                    ForEach(FocusSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("App names", selection: $model.settings.iconLabels) {
                    ForEach(IconLabels.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $model.settings.showShelf) {
                    Text("Top shelf")
                    Text("Big artwork for the focused app above the grid")
                }
                Toggle(isOn: $model.settings.shelfMotion) {
                    Text("Animated artwork")
                    Text("Light drifts slowly through the top shelf")
                }
                .disabled(!model.settings.showShelf)
                Toggle("Clock", isOn: $model.settings.showClock)
            }
            Section {
                Picker(selection: $model.settings.homeMotion) {
                    ForEach(HomeMotion.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Focus motion")
                    Text(model.settings.homeMotion.detail)
                }
            } header: {
                Text("Motion")
            } footer: {
                Text("With Reduce Motion on in System Settings, the Home Screen only fades.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $model.settings.showHints) {
                    Text("Control hints")
                    Text("Button tips on the Home Screen, the app switcher, Settings and the keyboard, for learning the remote")
                }
            }
        }
    }
}
