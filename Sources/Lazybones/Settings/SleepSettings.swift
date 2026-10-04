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
            if model.keyboardLight.isAvailable {
                Section {
                    Toggle(isOn: $model.settings.sleepSetsKeyboardLight) {
                        Text("Set keyboard brightness")
                        Text("Changes the keyboard backlight while Sleep Mode is on, and puts it back after")
                    }
                    LabeledContent("Keyboard brightness") {
                        Slider(value: $model.settings.sleepKeyboardLight, in: 0...1) {
                            Text("Keyboard brightness")
                        } minimumValueLabel: {
                            Image(systemName: "light.min").accessibilityLabel("Off")
                        } maximumValueLabel: {
                            Image(systemName: "light.max").accessibilityLabel("Brightest")
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                    .disabled(!model.settings.sleepSetsKeyboardLight)
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
