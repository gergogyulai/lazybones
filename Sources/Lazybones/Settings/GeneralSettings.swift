import SwiftUI

struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPane(page: .general) {
            Section {
                Toggle(isOn: $model.settings.startFullScreen) {
                    Text("Open in full screen")
                    Text("Takes effect the next time Lazybones opens")
                }
                Toggle(isOn: $model.settings.navigationSounds) {
                    Text("Play navigation sounds")
                    Text("A soft tone when focus moves, and a brighter one when you select")
                }
            }
            Section("Troubleshooting") {
                Toggle(isOn: $model.settings.showDebugOnLaunch) {
                    Text("Show debug overlay at launch")
                    Text("What each page reports about DRM, codecs and HDR. Press the remote’s Siri button to show it any time.")
                }
            }
        }
    }
}
