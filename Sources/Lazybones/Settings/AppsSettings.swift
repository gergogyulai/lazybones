import SwiftUI

/// Every app, in Home Screen order: a switch to show or hide each, drag to reorder, and a click
/// through to each app's own settings.
struct AppsSettings: View {
    @EnvironmentObject var model: AppModel
    /// Shows an app's own settings.
    let open: (String) -> Void
    /// The app open in the editor: a new one not yet added.
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
            ServiceEditor(service: e.service, isNew: e.isNew, save: model.save)
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
            Toggle("Show \(s.name) on the Home Screen", isOn: visibility(s.id))
                .labelsHidden()
                .toggleStyle(.switch)
            Button {
                open(s.id)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("\(s.name) Settings")
        }
        .contentShape(Rectangle())
        .onTapGesture { open(s.id) }
        .padding(.vertical, 2)
        .animation(.default, value: shown)
        .contextMenu {
            Button("Settings…") { open(s.id) }
            Button(shown ? "Hide from Home Screen" : "Show on Home Screen") { visibility(s.id).wrappedValue.toggle() }
            Divider()
            Button("Move Up") { move(from: i, to: i - 1) }.disabled(i == 0)
            Button("Move Down") { move(from: i, to: i + 1) }.disabled(i == services.count - 1)
            if !s.builtIn {
                Divider()
                Button("Remove \(s.name)", role: .destructive) { model.remove(s.id) }
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
}

extension AppModel {
    /// Takes an edited app back, or adds a new one at the end of the Home Screen.
    func save(_ s: Service) {
        if let i = settings.services.firstIndex(where: { $0.id == s.id }) {
            if settings.services[i] != s { settings.services[i] = s }
        } else {
            settings.services.append(s)
        }
    }

    /// Removes an app added in Settings. Built-in apps can only be hidden.
    func remove(_ id: String) {
        guard let s = settings.services.first(where: { $0.id == id }), !s.builtIn else { return }
        settings.services.removeAll { $0.id == id }
        settings.hidden.remove(id)
    }
}
