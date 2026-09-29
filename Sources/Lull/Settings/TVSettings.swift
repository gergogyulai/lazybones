import LGTV
import SwiftUI

struct TVSettings: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tv: TVLink
    @StateObject private var discovery = TVDiscovery()
    @State private var manualHost = ""
    @State private var resolving: String?
    @State private var pairError: String?

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
                if discovery.found.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Looking for LG TVs…").foregroundStyle(.secondary) }
                }
                ForEach(discovery.found) { found in
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
                if let pairError { Text(pairError).font(.caption).foregroundStyle(.red) }
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
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
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
                pairError = "Couldn't reach \(found.name). Check that it's on and on this network, or pair by address."
            }
        }
    }

    private var statusText: String { tv.status.summary }

    private var statusColor: Color {
        switch tv.status {
        case .connected: .green
        case .pairing, .connecting: .orange
        case .off, .failed: .red
        }
    }
}
