import SwiftUI

/// One app's own settings, reached from Apps: whether it's on the Home Screen, its name and address
/// (edited in a sheet), the extensions that work on it, and how the remote gets around it.
struct AppSettings: View {
    let id: String

    @EnvironmentObject private var model: AppModel
    @State private var editing = false

    var body: some View {
        if let s = model.settings.services.first(where: { $0.id == id }) {
            let service = binding(s)
            Form {
                Section {
                    heading(s)
                }
                Section {
                    Toggle("Show on Home Screen", isOn: Binding(
                        get: { !model.settings.hidden.contains(id) },
                        set: { if $0 { model.settings.hidden.remove(id) } else { model.settings.hidden.insert(id) } }
                    ))
                    LabeledContent {
                        Button("Edit…") { editing = true }
                    } label: {
                        Text(s.brand == nil ? "Name, Address and Appearance" : "Name and Address")
                        Text(s.url.absoluteString)
                    }
                }
                AppExtensionSections(service: service, extensions: model.extensions)
                NavigationSections(service: service, live: true)
            }
            .formStyle(.grouped)
            .navigationTitle(s.name)
            .sheet(isPresented: $editing) {
                ServiceEditor(service: s, isNew: false, save: model.save,
                              remove: s.builtIn ? nil : { model.remove(id) })
            }
        }
    }

    /// The app by its id rather than its place in the list, so removing it can't leave this
    /// pointing past the end.
    private func binding(_ fallback: Service) -> Binding<Service> {
        Binding(
            get: { model.settings.services.first { $0.id == id } ?? fallback },
            set: { s in
                if let i = model.settings.services.firstIndex(where: { $0.id == id }) { model.settings.services[i] = s }
            }
        )
    }

    private func heading(_ s: Service) -> some View {
        let shown = !model.settings.hidden.contains(id)
        return VStack(spacing: 10) {
            IconFace(service: s, height: 60, unit: 0.3)
                .frame(width: 100, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08)))
                .saturation(shown ? 1 : 0)
                .opacity(shown ? 1 : 0.5)
                .padding(.bottom, 4)
            Text(s.name)
                .font(.title2.weight(.semibold))
            Text(s.url.host() ?? s.url.absoluteString)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .animation(.default, value: shown)
        .accessibilityElement(children: .combine)
    }
}

/// A switch for each bundled extension that works on the app, and SponsorBlock's own settings,
/// since YouTube is the only place it works. uBlock Origin Lite's settings stay under Ad Blocking,
/// as they apply to every app.
private struct AppExtensionSections: View {
    @Binding var service: Service
    @ObservedObject var extensions: Extensions
    @State private var showingSponsorBlockOptions = false

    var body: some View {
        if extensions.applies(.uBlockOriginLite, to: service) {
            Section {
                Toggle(isOn: $service.blocksAds) {
                    Text("Block Ads")
                    Text("With uBlock Origin Lite")
                }
            } header: {
                Text("Ad Blocking")
            } footer: {
                footnote("The app reloads when you change this. Filter lists and your own filters are under Ad Blocking, for every app.")
            }
        }
        if extensions.applies(.sponsorBlock, to: service) {
            Section {
                Toggle(isOn: $service.skipsSponsors) {
                    Text("Skip Segments")
                    Text("Sponsors, intros and the like, as marked by SponsorBlock’s community")
                }
                LabeledContent("Status", value: extensions.status(.sponsorBlock).summary)
                LabeledContent {
                    Button("Open…") { showingSponsorBlockOptions = true }
                        .disabled(extensions.contexts[.sponsorBlock]?.optionsPageURL == nil)
                } label: {
                    Text("SponsorBlock Settings")
                    Text("Which kinds of segments to skip, mute or just mark, and how.")
                }
            } header: {
                Text("SponsorBlock")
            } footer: {
                footnote("The app reloads when you change this. Segments set to skip automatically are skipped without asking; SponsorBlock’s other notices can’t be reached with the remote.")
            }
            .sheet(isPresented: $showingSponsorBlockOptions) {
                ExtensionOptionsSheet(bundled: .sponsorBlock, extensions: extensions)
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }
}
