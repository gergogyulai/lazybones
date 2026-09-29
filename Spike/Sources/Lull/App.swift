import AppKit
import SiriRemote
import SwiftUI
import WebKit

@main
struct LullApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Lull", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.controlCenter)
                .environmentObject(model.tv)
                .environmentObject(model.keyboard)
                .frame(minWidth: 960, minHeight: 540)
                .onAppear {
                    guard model.settings.startFullScreen, !CommandLine.arguments.contains("--windowed") else { return }
                    DispatchQueue.main.async {
                        if let w = NSApp.windows.first(where: \.isVisible), !w.styleMask.contains(.fullScreen) {
                            w.toggleFullScreen(nil)
                        }
                    }
                }
        }
        .commands {
            CommandMenu("Lull") {
                Button("Home") { model.goHome() }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Control Center") { model.toggleControlCenter() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Toggle Debug") { model.showDebug.toggle() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Remote Simulator") { model.simulator.toggle() }.keyboardShortcut("r", modifiers: [.command, .option])
                Button("Reload") { model.reload() }.keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView().environmentObject(model).environmentObject(model.tv)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controlCenter: ControlCenter
    @EnvironmentObject var keyboard: KeyboardController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let s = model.active, let wv = model.web.views[s.id] {
                WebContainer(webView: wv).id(s.id).ignoresSafeArea()
            } else {
                LauncherView()
            }
            if keyboard.isVisible, let s = model.active {
                KeyboardView(accent: s.accent ?? s.color)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            VStack(alignment: .trailing, spacing: 12) {
                if let v = model.volumeHUD {
                    VolumeHUD(state: v).transition(.move(edge: .top).combined(with: .opacity))
                }
                if model.showDebug {
                    DebugOverlay()
                }
            }
            .padding(20)
            if controlCenter.isOpen {
                ControlCenterView()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.settingsRequests) { openSettings() }
    }
}

struct WebContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        attach(to: host)
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        if webView.superview !== host { attach(to: host) }
    }

    private func attach(to host: NSView) {
        webView.removeFromSuperview()
        webView.frame = host.bounds
        webView.autoresizingMask = [.width, .height]
        host.addSubview(webView)
        DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) }
    }
}

/// tvOS-style volume pill: speaker glyph and a level bar on a dark material.
struct VolumeHUD: View {
    let state: VolumeState

    var body: some View {
        let level = state.muted ? 0 : Double(state.level) / 100
        HStack(spacing: 14) {
            Image(systemName: state.muted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: level)
                .font(.system(size: 20, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30)
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: geo.size.width * level)
                    }
            }
            .frame(width: 180, height: 8)
            .animation(.spring(duration: 0.25), value: level)
            Text(state.target)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .allowsHitTesting(false)
    }
}

struct DebugOverlay: View {
    @EnvironmentObject var model: AppModel
    private let order = ["page", "load", "display", "MSE", "EME FairPlay", "EME Widevine", "encrypted",
                              "video", "codec", "HDR", "audio", "DRM", "video error", "play/pause"]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(remoteSummary).foregroundStyle(.secondary)
            // The page can only say HDR was asked for; the screen's live headroom shows it's on screen.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let screen = NSApp.windows.first(where: \.isVisible)?.screen,
                   screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 {
                    let now = screen.maximumExtendedDynamicRangeColorComponentValue
                    Text(String(format: "EDR headroom %.1f× of %.0f×", now, screen.maximumPotentialExtendedDynamicRangeColorComponentValue))
                        .foregroundStyle(now > 1.5 ? .green : .secondary)
                }
            }
            if let s = model.active {
                let r = model.reports[s.id] ?? [:]
                Text(s.name).bold().padding(.top, 4)
                ForEach(r.keys.sorted { rank($0) < rank($1) }, id: \.self) { k in
                    Text("\(k): \(r[k]!)").lineLimit(2).foregroundStyle(color(k, r[k]!))
                }
            }
            Divider().padding(.vertical, 4)
            ForEach(Array(model.events.suffix(6).enumerated()), id: \.offset) { _, e in
                Text(e).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 400, alignment: .leading)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
    }

    private var remoteSummary: String {
        let s = model.remoteStatus
        var parts = ["remote: \(s.buttons)", "touch \(s.touch ? "on" : "off")"]
        if let b = s.battery { parts.append("battery \(b.percent)%\(b.charging ? " ⚡" : "")") }
        return parts.joined(separator: " · ")
    }

    private func rank(_ k: String) -> (Int, String) { (order.firstIndex(of: k) ?? 99, k) }

    private func color(_ k: String, _ v: String) -> Color {
        if k == "video error" || v.hasPrefix("failed") { return .red }
        if k.hasPrefix("EME") { return v == "yes" ? .green : .orange }
        if k == "HDR" || k == "display" {
            if v.contains("unknown") { return .orange }
            return ["HDR", "HLG", "Dolby"].contains(where: v.hasPrefix) ? .green : .white
        }
        return .white
    }
}
