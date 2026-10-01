import SwiftUI

struct SleepSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPane(page: .sleepMode) {
            Section {
                Toggle(isOn: Binding(get: { model.sleepMode }, set: { model.setSleepMode($0) })) {
                    Text("Sleep Mode")
                    Text("Covers everything on every display, video included, and turns off when Lazybones quits")
                }
            }
            Section("Adjust") {
                // Like Night Shift: plain ends rather than numbers.
                LabeledContent("Dimming") {
                    Slider(value: $model.settings.sleepDim, in: 0...LauncherSettings.maxSleepDim) {
                        Text("Dimming")
                    } minimumValueLabel: {
                        Image(systemName: "sun.max").accessibilityLabel("Brighter")
                    } maximumValueLabel: {
                        Image(systemName: "sun.min").accessibilityLabel("Dimmer")
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
                LabeledContent("Blue light filter") {
                    Slider(value: $model.settings.sleepWarmth, in: 0...1) {
                        Text("Blue light filter")
                    } minimumValueLabel: {
                        Text("Less Warm").font(.caption)
                    } maximumValueLabel: {
                        Text("More Warm").font(.caption)
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
            }
            Section {
                Toggle(isOn: $model.settings.sleepInControlCenter) {
                    Text("Show in Control Center")
                    Text("Adds a tile to Control Center on the remote, so Sleep Mode is one click away")
                }
            }
        }
    }
}
