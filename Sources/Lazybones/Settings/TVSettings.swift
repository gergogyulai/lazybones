import LGTV
import SwiftUI

struct TVSettings: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tv: TVLink
    @StateObject private var discovery = TVDiscovery()
    @State private var manualHost = ""
    @State private var resolving: String?
    @State private var pairError: String?
    @State private var confirmingForget = false

    var body: some View {
        SettingsPane(page: .tv) {
            if let config = model.settings.tv {
                Section("Paired TV") {
                    LabeledContent {
                        Label {
                            Text(tv.status.summary)
                        } icon: {
                            Circle().fill(statusColor).frame(width: 8, height: 8)
                        }
                        .foregroundStyle(.secondary)
                    } label: {
                        Text(config.name)
                        Text(config.host)
                    }
                    if let o = tv.soundOutput { LabeledContent("Sound output", value: TVLink.soundOutputName(o)) }
                    if let v = tv.volume { LabeledContent("Volume", value: tv.muted == true ? "Muted" : "\(v)") }
                    HStack {
                        Spacer()
                        Button("Forget TV…") { confirmingForget = true }
                        Button("Reconnect") { tv.connect() }
                    }
                }
            }

            Section {
                if discovery.found.isEmpty {
                    LabeledContent("Looking for LG TVs…") { ProgressView().controlSize(.small) }
                        .foregroundStyle(.secondary)
                }
                ForEach(discovery.found) { found in
                    let paired = model.settings.tv?.name == found.name
                    LabeledContent(found.name) {
                        if resolving == found.name {
                            ProgressView().controlSize(.small)
                        } else if paired {
                            Label("Paired", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Pair") { pair(found) }.disabled(resolving != nil)
                        }
                    }
                }
                LabeledContent("Pair by address") {
                    HStack {
                        TextField("Address", text: $manualHost, prompt: Text("192.168.1.20"))
                            .labelsHidden()
                            .frame(width: 150)
                            .onSubmit(pairManually)
                        Button("Pair", action: pairManually).disabled(trimmedHost.isEmpty)
                    }
                }
            } header: {
                Text("TVs on This Network")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let pairError { Text(pairError).foregroundStyle(.red) }
                    Text("Pairing shows a prompt on the TV; accept it with the TV’s remote. The TV needs “LG Connect Apps” (or “Mobile TV On”) turned on.")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }

            Section {
                Toggle(isOn: $model.settings.tvVolume) {
                    Text("Control TV volume over HDMI")
                    Text("Volume steps reach a soundbar on HDMI ARC through the TV. Outputs with no volume control of their own fall back to the apps’ volume.")
                }
            }
        }
        .confirmationDialog("Forget \(model.settings.tv?.name ?? "this TV")?", isPresented: $confirmingForget) {
            Button("Forget TV", role: .destructive) { model.settings.tv = nil }
        } message: {
            Text("Lazybones will stop controlling its volume and power. You’ll need to accept a new prompt on the TV to pair it again.")
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    private var trimmedHost: String { manualHost.trimmingCharacters(in: .whitespaces) }

    private func pairManually() {
        guard !trimmedHost.isEmpty else { return }
        model.settings.tv = TVConfig(name: "LG TV", host: trimmedHost)
    }

    private func pair(_ found: FoundTV) {
        resolving = found.name
        Task {
            let host = await TVDiscovery.resolve(found)
            resolving = nil
            if let host {
                pairError = nil
                model.settings.tv = TVConfig(name: found.name, host: host)
            } else {
                pairError = "Couldn’t reach \(found.name). Check that it’s on and on this network, or pair by address."
            }
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
