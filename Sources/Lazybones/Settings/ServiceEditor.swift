import SwiftUI

struct ServiceEditor: View {
    @Binding var service: Service
    @Binding var visible: Bool
    @State private var urlText = ""

    var body: some View {
        Form {
            Section {
                IconFace(service: service, height: 108, unit: 0.5)
                    .frame(width: 180, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                Toggle("Show on Home Screen", isOn: $visible)
            }
            Section("App") {
                TextField("Name", text: $service.name)
                TextField("URL", text: $urlText)
                    .onChange(of: urlText) { _, text in
                        if let url = Service.url(from: text) { service.url = url }
                    }
                if Service.url(from: urlText) == nil {
                    Text("Enter a web address, like example.com or http://192.168.1.5:8096.")
                        .font(.caption).foregroundStyle(.red)
                }
                TextField("Top shelf tagline", text: $service.tagline)
            }
            Section("Appearance") {
                LabeledContent("Symbol") {
                    HStack {
                        TextField("SF Symbol name", text: $service.symbol).labelsHidden()
                        Image(systemName: service.symbol).frame(width: 24)
                    }
                }
                ColorPicker("Color", selection: color(\.tint), supportsOpacity: false)
                ColorPicker("Highlight", selection: Binding(
                    get: { service.accent ?? service.color },
                    set: { service.accentTint = RGB($0) }
                ), supportsOpacity: false)
            }
            Section {
                Picker("Identify as", selection: $service.agent) {
                    Text("Safari").tag(Service.Agent.safari)
                    Text("Smart TV").tag(Service.Agent.tv)
                }
                let handles = ServiceModules.handlesNavigation(service)
                Toggle("Remote navigation for desktop sites", isOn: handles ? .constant(false) : $service.spatialNav)
                    .disabled(handles)
                    .help(handles ? "\(service.name) handles remote navigation itself." : "")
            } header: {
                Text("Browser")
            } footer: {
                Text("Smart TV serves TV layouts like youtube.com/tv. Remote navigation moves focus between links and buttons with the clickpad. Changes reload the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { urlText = service.url.absoluteString }
    }

    private func color(_ path: WritableKeyPath<Service, RGB>) -> Binding<Color> {
        Binding(get: { service[keyPath: path].color }, set: { service[keyPath: path] = RGB($0) })
    }
}
