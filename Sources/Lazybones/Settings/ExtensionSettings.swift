import SwiftUI
import WebKit

struct AdBlockingSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ExtensionPane(page: .adBlocking, bundled: .uBlockOriginLite, extensions: model.extensions,
                      isOn: \.blocksAds, header: "Block Ads In",
                      footer: "An app reloads when you change this. YouTube’s TV app gets its ads with its videos, where uBlock Origin Lite can’t reach them, so Lazybones takes them out itself while YouTube blocks ads.")
    }
}

/// A bundled extension: whether it loaded, its own settings page in a sheet, and a switch for
/// each app it works on.
private struct ExtensionPane: View {
    let page: SettingsScreen.Page
    let bundled: BundledExtension
    @ObservedObject var extensions: Extensions
    let isOn: WritableKeyPath<Service, Bool>
    let header: String
    let footer: String

    @EnvironmentObject private var model: AppModel
    @State private var showingOptions = false

    var body: some View {
        SettingsPane(page: page) {
            Section {
                LabeledContent(bundled.name, value: extensions.status(bundled).summary)
                LabeledContent {
                    Button("Open…") { showingOptions = true }
                        .disabled(extensions.contexts[bundled]?.optionsPageURL == nil)
                } label: {
                    Text("\(bundled.name) Settings")
                    Text(bundled == .uBlockOriginLite
                         ? "Filter lists, filtering modes and your own filters. They apply to every app that blocks ads."
                         : "Which kinds of segments to skip, mute or just mark, and how.")
                }
            }
            Section {
                let apps = model.settings.services.indices.filter { extensions.applies(bundled, to: model.settings.services[$0]) }
                if apps.isEmpty {
                    Text("None of your apps")
                        .foregroundStyle(.secondary)
                }
                ForEach(apps, id: \.self) { i in
                    let s = model.settings.services[i]
                    Toggle(isOn: $model.settings.services[i][dynamicMember: isOn]) {
                        HStack(spacing: 12) {
                            IconFace(service: s, height: 28, compact: true)
                                .frame(width: 46, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.08)))
                            Text(s.name)
                        }
                    }
                    .toggleStyle(.switch)
                }
            } header: {
                Text(header)
            } footer: {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingOptions) {
            ExtensionOptionsSheet(bundled: bundled, extensions: extensions)
        }
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
