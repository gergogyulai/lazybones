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
                Toggle(isOn: $model.settings.showShelf) {
                    Text("Top shelf")
                    Text("Big artwork for the focused app above the grid")
                }
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
