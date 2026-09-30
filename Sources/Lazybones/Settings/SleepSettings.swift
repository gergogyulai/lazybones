import SwiftUI

struct SleepSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Sleep Mode", isOn: Binding(get: { model.sleepMode }, set: { model.setSleepMode($0) }))
            } footer: {
                Text("Dims the screen and filters blue light for watching late at night. It covers everything on every display, video included, and turns off when Lazybones quits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Adjust") {
                LabeledContent("Dimming") {
                    Slider(value: $model.settings.sleepDim, in: 0...LauncherSettings.maxSleepDim).frame(width: 240)
                }
                LabeledContent("Blue light filter") {
                    Slider(value: $model.settings.sleepWarmth, in: 0...1).frame(width: 240)
                }
            }
            Section {
                Toggle("Show Sleep Mode in Control Center", isOn: $model.settings.sleepInControlCenter)
            } footer: {
                Text("Adds a tile to Control Center on the remote, so Sleep Mode is one click away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
