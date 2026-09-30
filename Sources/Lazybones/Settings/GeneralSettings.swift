import SwiftUI

struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Open in full screen", isOn: $model.settings.startFullScreen)
                Toggle("Show debug overlay at launch", isOn: $model.settings.showDebugOnLaunch)
            }
            Section {
                Toggle("Show when a text field is selected", isOn: $model.settings.keyboard)
                Picker("Layout", selection: $model.settings.keyboardLayout) {
                    Text("ABC").tag(KeyboardLayout.abc)
                    Text("QWERTY").tag(KeyboardLayout.qwerty)
                }
                .pickerStyle(.segmented)
                LabeledContent("Suggestions") {
                    Button("Clear Recent Searches and Emails") { KeyboardHistory.clear() }
                }
            } header: {
                Text("On-Screen Keyboard")
            } footer: {
                Text("Adapts to each field: email, web address, search, number and code fields get their own keys and suggestions. Sites in Smart TV mode use their own keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
