import SwiftUI

/// Every app, in Home Screen order: a switch to show or hide each, drag to reorder, and Details…
/// for editing one in a sheet.
struct AppsSettings: View {
    @EnvironmentObject var model: AppModel
    /// The app open in the editor: one already on the list, or a new one not yet added.
    @State private var editing: Editing?
    @State private var confirmingRestore = false

    struct Editing: Identifiable {
        let service: Service
        let isNew: Bool
        var id: String { service.id }
    }

    var body: some View {
        SettingsPane(page: .apps) {
            Section {
                ForEach(model.settings.services) { s in
                    row(s)
                }
                .onMove { model.settings.services.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Home Screen")
            } footer: {
                HStack {
                    Text("Drag apps to change their order.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults…") { confirmingRestore = true }
                    Button("Add App…") { editing = Editing(service: .custom(), isNew: true) }
                }
            }
        }
        .sheet(item: $editing) { e in
            ServiceEditor(service: e.service, isNew: e.isNew, save: save,
                          remove: e.isNew || e.service.builtIn ? nil : { remove(e.service.id) })
        }
        .confirmationDialog("Restore the default apps?", isPresented: $confirmingRestore) {
            Button("Restore Defaults", role: .destructive) {
                model.settings.services = Service.defaults
                model.settings.hidden = []
            }
        } message: {
            Text("Apps you added are removed, and the built-in apps go back to their original names, colors and order.")
        }
    }

    private func row(_ s: Service) -> some View {
        let shown = !model.settings.hidden.contains(s.id)
        let services = model.settings.services
        let i = services.firstIndex { $0.id == s.id } ?? 0

        return HStack(spacing: 12) {
            IconFace(service: s, height: 28, compact: true)
                .frame(width: 46, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.08)))
                .saturation(shown ? 1 : 0)
                .opacity(shown ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name)
                    .foregroundStyle(shown ? .primary : .secondary)
                Text(s.url.host() ?? s.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editing = Editing(service: s, isNew: false)
            } label: {
                Image(systemName: "info.circle")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Details")
            .accessibilityLabel("\(s.name) Details")
            Toggle("Show \(s.name) on the Home Screen", isOn: visibility(s.id))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
        .animation(.default, value: shown)
        .contextMenu {
            Button("Details…") { editing = Editing(service: s, isNew: false) }
            Button(shown ? "Hide from Home Screen" : "Show on Home Screen") { visibility(s.id).wrappedValue.toggle() }
            Divider()
            Button("Move Up") { move(from: i, to: i - 1) }.disabled(i == 0)
            Button("Move Down") { move(from: i, to: i + 1) }.disabled(i == services.count - 1)
            if !s.builtIn {
                Divider()
                Button("Remove \(s.name)", role: .destructive) { remove(s.id) }
            }
        }
    }

    private func visibility(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !model.settings.hidden.contains(id) },
            set: { if $0 { model.settings.hidden.remove(id) } else { model.settings.hidden.insert(id) } }
        )
    }

    private func move(from i: Int, to j: Int) {
        guard model.settings.services.indices.contains(j) else { return }
        withAnimation { model.settings.services.swapAt(i, j) }
    }

    /// Takes an edited app back, or adds a new one at the end of the Home Screen.
    private func save(_ s: Service) {
        if let i = model.settings.services.firstIndex(where: { $0.id == s.id }) {
            if model.settings.services[i] != s { model.settings.services[i] = s }
        } else {
            model.settings.services.append(s)
        }
    }

    private func remove(_ id: String) {
        guard let s = model.settings.services.first(where: { $0.id == id }), !s.builtIn else { return }
        model.settings.services.removeAll { $0.id == id }
        model.settings.hidden.remove(id)
    }
}
