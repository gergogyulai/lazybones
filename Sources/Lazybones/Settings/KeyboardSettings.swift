import SwiftUI

struct KeyboardSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmingClear = false

    var body: some View {
        SettingsPane(page: .keyboard) {
            Section {
                Toggle(isOn: $model.settings.keyboard) {
                    Text("Show when a text field is selected")
                    Text("Adapts to each field: email, web address, search, number and code fields get their own keys and suggestions")
                }
                Picker("Layout", selection: $model.settings.keyboardLayout) {
                    Text("ABC").tag(KeyboardLayout.abc)
                    Text("QWERTY").tag(KeyboardLayout.qwerty)
                }
                .pickerStyle(.segmented)
                .disabled(!model.settings.keyboard)
            } footer: {
                Text("Sites in Smart TV mode use their own keyboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    Button("Clear History…") { confirmingClear = true }
                } label: {
                    Text("Suggestions")
                    Text("Recent searches and email addresses, offered as you type")
                }
            }
        }
        .confirmationDialog("Clear recent searches and email addresses?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { KeyboardHistory.clear() }
        } message: {
            Text("The keyboard will stop suggesting them. This can’t be undone.")
        }
    }
}
