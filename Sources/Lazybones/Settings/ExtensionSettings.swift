import SwiftUI
import WebKit

/// uBlock Origin Lite: whether it loaded, how hard it filters and what else it blocks, and at the
/// bottom, a way to its own settings for everything else.
struct AdBlockingSettings: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let extensions = model.extensions
        SettingsPane(page: .adBlocking) {
            Section {
                LabeledContent(BundledExtension.uBlockOriginLite.name,
                               value: extensions.status(.uBlockOriginLite).summary)
            } footer: {
                Text("Turn ad blocking on or off for an app in its own settings. YouTube’s TV app gets its ads with its videos, where uBlock Origin Lite can’t reach them, so Lazybones takes them out itself.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            AdBlockOptionsSections(options: extensions.adBlock)
            Section {
                LabeledContent {
                    Button("Open…") { openWindow(id: AdBlockerSettingsWindow.windowID) }
                        .disabled(extensions.contexts[.uBlockOriginLite]?.optionsPageURL == nil)
                } label: {
                    Text("uBlock Origin Lite Settings")
                    Text("Every filter list, filtering modes for single sites, and your own filters.")
                }
            }
        }
    }
}

/// How hard uBlock Origin Lite filters, and what else it blocks, for every app that blocks ads.
private struct AdBlockOptionsSections: View {
    @ObservedObject var options: AdBlockOptions

    var body: some View {
        if let level = options.level {
            Section {
                Picker("Blocking Level", selection: Binding(get: { level }, set: { options.set($0) })) {
                    ForEach(AdBlockOptions.Level.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(level.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(AdBlockOptions.Extra.allCases) { extra in
                    Toggle(isOn: Binding(get: { options.isOn(extra) }, set: { options.set(extra, on: $0) })) {
                        Text(extra.title)
                        Text(extra.detail)
                    }
                    .toggleStyle(.switch)
                }
            } header: {
                Text("Also Block")
            } footer: {
                Text("These apply to every app that blocks ads, the next time its page loads.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// uBlock Origin Lite's own settings page in a window of its own, opened from the Mac's Settings
/// and from the TV's. What's changed there shows in Lazybones' settings once it closes.
struct AdBlockerSettingsWindow: View {
    static let windowID = "ublock-settings"
    let extensions: Extensions

    var body: some View {
        OptionsPage(bundled: .uBlockOriginLite, extensions: extensions)
            .frame(minWidth: 700, minHeight: 500)
            .onDisappear { Task { await extensions.adBlock.refresh() } }
    }
}

/// The extension's own settings page, as its options page would show in a browser.
struct ExtensionOptionsSheet: View {
    let bundled: BundledExtension
    let extensions: Extensions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            OptionsPage(bundled: bundled, extensions: extensions)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 860, height: 680)
    }
}

private struct OptionsPage: NSViewRepresentable {
    let bundled: BundledExtension
    let extensions: Extensions

    func makeNSView(context: Context) -> NSView { extensions.makeOptionsPage(for: bundled) ?? NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
