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
            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }()
}
