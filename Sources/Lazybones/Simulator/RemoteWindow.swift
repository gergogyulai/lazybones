import SiriRemote
import SwiftUI

/// The simulator window, laid out like Xcode's Simulator: the device's name and state in the title
/// bar with its options beside them, the device in the middle, and the gestures that are awkward
/// with a mouse in a glass bar under it.
struct RemoteWindowContent: View {
    @EnvironmentObject var sim: RemoteSimulator
    @AppStorage(RemoteSimulator.Preference.showsEvents) private var showsEvents = true
    @AppStorage(RemoteSimulator.Preference.showsKeys) private var showsKeys = true
    @AppStorage(RemoteSimulator.Preference.keepsOnTop) private var keepsOnTop = true

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            RemoteView()
                .padding(.top, 12)
                .padding(.horizontal, 64)
            EventReadout()
                .frame(height: showsEvents ? 54 : 16)
                .opacity(showsEvents ? 1 : 0)
            RemoteActions()
                .padding(.bottom, 16)
        }
        .fixedSize()
        // One surface from the title bar down, as in Simulator.
        .background(.windowBackground)
    }

    /// Drawn into the window's (transparent) title bar, beside the traffic lights: the name and
    /// state, and the options in a glass pill.
    private var titleBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Siri Remote").font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                Button {
                    keepsOnTop.toggle()
                } label: {
                    Image(systemName: keepsOnTop ? "pin.fill" : "pin").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .help(keepsOnTop ? "Floating above other windows" : "Keep the remote above other windows")
                .accessibilityLabel("Keep on Top")
                .accessibilityValue(keepsOnTop ? "on" : "off")
                Menu {
                    Toggle("Keep on Top", isOn: $keepsOnTop)
                    Toggle("Show Key Labels", isOn: $showsKeys)
                    Toggle("Show Events", isOn: $showsEvents)
                    Divider()
                    Text("Drag or scroll on the clickpad to swipe")
                    Text("⇧ arrow keys swipe too")
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .accessibilityLabel("Options")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 4)
            .glassSurface(Capsule(), interactive: true)
        }
        // Clear of the traffic lights, and as tall as a unified title bar so they sit centred on it.
        .padding(.leading, 90)
        .padding(.trailing, 10)
        .frame(height: 52)
    }

    private var subtitle: String {
        switch sim.hardware {
        case .disconnected: "Simulated"
        case .shared, .exclusive: "Simulated · real remote connected"
        }
    }
}

/// The gestures that take a timed press on the hardware, as buttons: the TV button clicked, double
/// clicked (the app switcher) and held (Control Center), and Siri (the debug overlay).
private struct RemoteActions: View {
    @EnvironmentObject var sim: RemoteSimulator

    var body: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    action("Home", "Click TV", "tv") { sim.tap(.home) }
                    action("App Switcher", "Double-click TV", "square.stack") { sim.doubleClickHome() }
                    action("Control Center", "Hold TV", "switch.2") { sim.holdHome() }
                }
                .padding(.horizontal, 6)
                .glassSurface(Capsule(), interactive: true)
                action("Debug Overlay", "Siri", "ladybug") { sim.tap(.siri) }
                    .padding(.horizontal, 6)
                    .glassSurface(Capsule(), interactive: true)
            }
        }
    }

    private func action(_ name: String, _ gesture: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keys are remote buttons here (Space is Play/Pause), so nothing else may take them.
        .focusable(false)
        .foregroundStyle(.primary)
        .help("\(name) (\(gesture))")
        .accessibilityLabel(name)
    }
}

/// What the remote just sent, newest at the bottom, with where it came from when that wasn't here.
private struct EventReadout: View {
    @EnvironmentObject var sim: RemoteSimulator

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(sim.echoes.suffix(3).enumerated()), id: \.element.id) { i, e in
                HStack(spacing: 4) {
                    switch e.origin {
                    case .simulator: EmptyView()
                    case .hardware: tag("REMOTE", .blue)
                    case .control: tag("CTL", .purple)
                    }
                    Text(e.text)
                }
                .opacity(i == min(sim.echoes.count, 3) - 1 ? 1 : 0.45)
                .transition(.opacity)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: sim.echoes)
        .allowsHitTesting(false)
    }

    private func tag(_ s: String, _ c: Color) -> some View {
        Text(s).font(.system(size: 7, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(c.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
    }
}
