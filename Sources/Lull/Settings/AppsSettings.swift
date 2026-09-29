import SwiftUI

struct AppsSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.settings.services) { s in
                        HStack(spacing: 10) {
                            Toggle("Show", isOn: visibility(s.id)).labelsHidden()
                            IconFace(service: s, height: 22, unit: 0.1)
                                .frame(width: 36, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Text(s.name)
                                .foregroundStyle(model.settings.hidden.contains(s.id) ? .secondary : .primary)
                        }
                        .tag(s.id)
                    }
                    .onMove { model.settings.services.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 4) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 20, height: 20) }
                        .help("Add a web app")
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 20, height: 20) }
                        .disabled(selectedService?.builtIn ?? true)
                        .help("Remove (built-in apps can only be hidden)")
                    Spacer()
                    Button("Restore Defaults") {
                        model.settings.services = Service.defaults
                        model.settings.hidden = []
                        selection = nil
                    }
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 250)

            Divider()

            if let i = model.settings.services.firstIndex(where: { $0.id == selection }) {
                ServiceEditor(service: $model.settings.services[i], visible: visibility(model.settings.services[i].id))
                    .id(model.settings.services[i].id)
            } else {
                Text("Select an app to edit it.\nDrag to reorder the Home Screen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selectedService: Service? { model.settings.services.first { $0.id == selection } }

    private func visibility(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !model.settings.hidden.contains(id) },
            set: { if $0 { model.settings.hidden.remove(id) } else { model.settings.hidden.insert(id) } }
        )
    }

    private func add() {
        let s = Service.custom()
        model.settings.services.append(s)
        selection = s.id
    }

    private func remove() {
        guard let s = selectedService, !s.builtIn else { return }
        model.settings.services.removeAll { $0.id == s.id }
        model.settings.hidden.remove(s.id)
        selection = nil
    }
}
