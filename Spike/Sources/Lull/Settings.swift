import SwiftUI

/// Everything the user can configure about the launcher, persisted as JSON in UserDefaults.
struct LauncherSettings: Codable, Equatable {
    /// All apps in Home Screen order, visible or not.
    var services = Service.defaults
    var hidden: Set<String> = []
    var columns = 5
    var showShelf = true
    var showHints = true
    var showDebugOnLaunch = true
    var startFullScreen = true
    var tv: TVConfig?
    /// Send volume to the paired TV when audio goes out over HDMI.
    var tvVolume = true
    /// Show the on-screen keyboard when a text field in a page is focused.
    var keyboard = true
    var keyboardLayout = KeyboardLayout.abc

    var visibleServices: [Service] { services.filter { !hidden.contains($0.id) } }

    private static let key = "launcherSettings"

    init() {}

    // Field by field, so settings saved by an older build still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LauncherSettings()
        services = try c.decodeIfPresent([Service].self, forKey: .services) ?? d.services
        hidden = try c.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? d.hidden
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? d.columns
        showShelf = try c.decodeIfPresent(Bool.self, forKey: .showShelf) ?? d.showShelf
        showHints = try c.decodeIfPresent(Bool.self, forKey: .showHints) ?? d.showHints
        showDebugOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showDebugOnLaunch) ?? d.showDebugOnLaunch
        startFullScreen = try c.decodeIfPresent(Bool.self, forKey: .startFullScreen) ?? d.startFullScreen
        tv = try c.decodeIfPresent(TVConfig.self, forKey: .tv)
        tvVolume = try c.decodeIfPresent(Bool.self, forKey: .tvVolume) ?? d.tvVolume
        keyboard = try c.decodeIfPresent(Bool.self, forKey: .keyboard) ?? d.keyboard
        keyboardLayout = try c.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout) ?? d.keyboardLayout
    }

    static func load() -> LauncherSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              var s = try? JSONDecoder().decode(LauncherSettings.self, from: data) else { return LauncherSettings() }
        // Built-ins added since the settings were saved go after their predecessor in the default order.
        for (i, d) in Service.defaults.enumerated() where !s.services.contains(where: { $0.id == d.id }) {
            let after = Service.defaults[..<i].last { p in s.services.contains { $0.id == p.id } }
            let at = after.flatMap { p in s.services.firstIndex { $0.id == p.id } }.map { $0 + 1 } ?? 0
            s.services.insert(d, at: at)
        }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            AppsSettings().tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            LayoutSettings().tabItem { Label("Layout", systemImage: "rectangle.3.group") }
            TVSettings().tabItem { Label("TV", systemImage: "tv") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 760, height: 520)
    }
}

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
                        if let url = URL(string: text), ["http", "https"].contains(url.scheme), url.host() != nil {
                            service.url = url
                        }
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

struct LayoutSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Picker("Apps per row", selection: $model.settings.columns) {
                ForEach(3...7, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Top shelf", isOn: $model.settings.showShelf)
            Toggle("Show control hints", isOn: $model.settings.showHints)
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Open in full screen", isOn: $model.settings.startFullScreen)
                Toggle("Show debug overlay at launch", isOn: $model.settings.showDebugOnLaunch)
            }
            Section {
                Toggle("Show when a text field is selected", isOn: $model.settings.keyboard)
                Picker("Layout", selection: $model.settings.keyboardLayout) {
                    Text("ABC").tag(KeyboardLayout.abc)
                    Text("QWERTY").tag(KeyboardLayout.qwerty)
                }
                .pickerStyle(.segmented)
                LabeledContent("Suggestions") {
                    Button("Clear Recent Searches and Emails") { KeyboardHistory.clear() }
                }
            } header: {
                Text("On-Screen Keyboard")
            } footer: {
                Text("Adapts to each field: email, web address, search, number and code fields get their own keys and suggestions. Sites in Smart TV mode use their own keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct TVSettings: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tv: TVLink
    @State private var manualHost = ""
    @State private var resolving: String?

    var body: some View {
        Form {
            Section {
                if let config = model.settings.tv {
                    LabeledContent(config.name) {
                        HStack(spacing: 8) {
                            Circle().fill(statusColor).frame(width: 8, height: 8)
                            Text(statusText).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Address", value: config.host)
                    if let o = tv.soundOutput { LabeledContent("TV sound output", value: TVLink.soundOutputName(o)) }
                    if let v = tv.volume { LabeledContent("TV volume", value: "\(v)\(tv.muted == true ? " (muted)" : "")") }
                    HStack {
                        Button("Reconnect") { tv.connect() }
                        Button("Forget TV", role: .destructive) { model.settings.tv = nil }
                    }
                } else {
                    Text("No TV paired.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Paired TV")
            }

            Section {
                if tv.discovered.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Looking for LG TVs…").foregroundStyle(.secondary) }
                }
                ForEach(tv.discovered) { found in
                    LabeledContent(found.name) {
                        if resolving == found.name {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(model.settings.tv?.name == found.name ? "Paired" : "Pair") { pair(found) }
                                .disabled(model.settings.tv?.name == found.name || resolving != nil)
                        }
                    }
                }
                LabeledContent("Or by address") {
                    HStack {
                        TextField("192.168.1.20", text: $manualHost).labelsHidden().frame(width: 160)
                        Button("Pair") { model.settings.tv = TVConfig(name: "LG TV", host: manualHost.trimmingCharacters(in: .whitespaces)) }
                            .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("LG webOS TVs on this network")
            } footer: {
                Text("Pairing shows a prompt on the TV; accept it with the TV's remote. The TV must have \"LG Connect Apps\" (or \"Mobile TV On\") enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Control TV volume when audio goes out over HDMI", isOn: $model.settings.tvVolume)
            } footer: {
                Text("Macs can't send HDMI-CEC, so Lull controls the TV over the network instead. Volume steps reach a soundbar on HDMI ARC through the TV. Outputs with no volume control of their own and no TV fall back to adjusting the apps' volume.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { tv.startDiscovery() }
        .onDisappear { tv.stopDiscovery() }
    }

    private func pair(_ found: TVLink.Found) {
        resolving = found.name
        Task {
            let host = await TVLink.resolve(found)
            resolving = nil
            if let host { model.settings.tv = TVConfig(name: found.name, host: host) }
        }
    }

    private var statusText: String {
        switch tv.status {
        case .off: "Not connected"
        case .connecting: "Connecting…"
        case .pairing: "Accept the prompt on your TV"
        case .connected: "Connected"
        case let .failed(reason): "Unavailable: \(reason)"
        }
    }

    private var statusColor: Color {
        switch tv.status {
        case .connected: .green
        case .pairing, .connecting: .orange
        case .off, .failed: .red
        }
    }
}
