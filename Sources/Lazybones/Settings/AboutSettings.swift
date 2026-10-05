import AppKit
import SwiftUI

/// The About pane: the same details as the About window, for finding them from Settings.
struct AboutSettings: View {
    @State private var copied = false

    var body: some View {
        SettingsPane(page: .about) {
            Section {
                ForEach(AboutInfo.current.rows, id: \.label) { row in
                    LabeledContent(row.label) {
                        Text(row.value)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                }
            } footer: {
                HStack {
                    Link("Source Code", destination: AboutInfo.repository)
                    Link("Report an Issue", destination: AboutInfo.issues)
                    Spacer()
                    Button(copied ? "Copied" : "Copy Info", action: copy)
                }
            }
            Section {
            } footer: {
                Text(AboutInfo.credits)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AboutInfo.current.plainText, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
