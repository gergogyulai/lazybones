import CoreAudio
import LGTV
import MacSystem
import SiriRemote
import SwiftUI

struct ControlCenterView: View {
    @EnvironmentObject var diagnostics: Diagnostics
    @EnvironmentObject var cc: ControlCenter
    @EnvironmentObject var tv: TVLink
    /// Carries out an action that reaches outside the panel.
    let perform: (ControlCenter.Action) -> Void

    var body: some View {
        GeometryReader { geo in
            let u = max(geo.size.width / 1920, 0.55)
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { perform(.close) }

                VStack(alignment: .leading, spacing: 18 * u) {
                    header(u)
                    HStack(spacing: 18 * u) {
                        smallTile(.home, "house.fill", "Home", u)
                        smallTile(.displayOff, "power", "Display Off", u)
                        if tv.status == .connected { smallTile(.tvOff, "tv", "Turn Off TV", u) }
                    }
                    volumeTile(u)
                    outputTile(u)
                    networkCard(u)
                    HStack(spacing: 18 * u) {
                        if cc.canReload { smallTile(.reload, "arrow.clockwise", "Reload", u) }
                        if cc.showsSleepMode {
                            smallTile(.sleepMode, cc.sleepModeOn ? "moon.zzz.fill" : "moon.zzz", "Sleep Mode", u,
                                      lit: cc.sleepModeOn)
                        }
                        smallTile(.debug, "ladybug.fill", diagnostics.isVisible ? "Debug On" : "Debug Off", u,
                                  lit: diagnostics.isVisible)
                        smallTile(.settings, "gearshape.fill", "Settings", u)
                    }
                }
                .padding(28 * u)
                .frame(width: 580 * u)
                .glassSurface(RoundedRectangle(cornerRadius: 48 * u, style: .continuous))
                .environment(\.colorScheme, .dark)
                .padding(40 * u)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
    }

    private func header(_ u: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 2 * u) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 60 * u, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(ctx.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.system(size: 20 * u, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            if let b = diagnostics.remote.battery {
                HStack(spacing: 6 * u) {
                    Image(systemName: "appletvremote.gen4.fill")
                    Text("\(b.percent)%").monospacedDigit()
                    if b.charging { Image(systemName: "bolt.fill").foregroundStyle(.yellow) }
                }
                .font(.system(size: 18 * u, weight: .semibold))
                .padding(.horizontal, 12 * u)
                .padding(.vertical, 7 * u)
                .background(.white.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 6 * u)
        .padding(.bottom, 6 * u)
    }

    private func smallTile(_ item: ControlCenter.Item, _ symbol: String, _ label: String, _ u: CGFloat,
                           lit: Bool = false) -> some View {
        let focused = cc.focus == item && !cc.outputExpanded
        return VStack(alignment: .leading, spacing: 10 * u) {
            Image(systemName: symbol)
                .font(.system(size: 30 * u, weight: .semibold))
                .foregroundStyle(lit && !focused ? .blue : focused ? .black : .white)
            Text(label)
                .font(.system(size: 19 * u, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20 * u)
        .tile(focused: focused, u: u)
        .onTapGesture { cc.focus = item; if let a = cc.handle(.select) { perform(a) } }
    }

    private func volumeTile(_ u: CGFloat) -> some View {
        let focused = cc.focus == .volume && !cc.outputExpanded
        let muted = cc.volume?.muted ?? false
        let level = muted ? 0 : Double(cc.volume?.level ?? 0) / 100
        return VStack(alignment: .leading, spacing: 14 * u) {
            HStack {
                Text("Volume").font(.system(size: 19 * u, weight: .semibold))
                if let target = cc.volume?.target {
                    Text(target).font(.system(size: 16 * u, weight: .medium)).opacity(0.6).lineLimit(1)
                }
                Spacer()
                Text(focused ? "◀ ▶ adjust · click to mute" : muted ? "Muted" : "\(cc.volume?.level ?? 0)%")
                    .font(.system(size: 16 * u, weight: .medium))
                    .opacity(0.6)
            }
            HStack(spacing: 14 * u) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: level)
                    .font(.system(size: 24 * u, weight: .semibold))
                    .frame(width: 34 * u)
                GeometryReader { g in
                    Capsule().fill(focused ? .black.opacity(0.15) : .white.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule().fill(focused ? .black : .white).frame(width: g.size.width * level)
                        }
                }
                .frame(height: 10 * u)
                .animation(.spring(duration: 0.25), value: level)
            }
        }
        .padding(20 * u)
        .tile(focused: focused, u: u)
        .onTapGesture { cc.focus = .volume }
    }

    private func outputTile(_ u: CGFloat) -> some View {
        let focused = cc.focus == .output && !cc.outputExpanded
        let current = cc.outputs.first { $0.id == cc.currentOutput }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14 * u) {
                Image(systemName: current?.symbol ?? "speaker.wave.2.fill")
                    .font(.system(size: 26 * u, weight: .semibold))
                    .frame(width: 34 * u)
                VStack(alignment: .leading, spacing: 2 * u) {
                    Text("Audio Output").font(.system(size: 15 * u, weight: .medium)).opacity(0.6)
                    Text(current?.name ?? "Unknown").font(.system(size: 20 * u, weight: .semibold)).lineLimit(1)
                    if current?.isDisplay == true, tv.status == .connected, let o = tv.soundOutput {
                        Text("\(tv.name) → \(TVLink.soundOutputName(o))")
                            .font(.system(size: 15 * u, weight: .medium)).opacity(0.6).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 16 * u, weight: .bold))
                    .rotationEffect(.degrees(cc.outputExpanded ? 180 : 0))
                    .opacity(0.6)
            }
            .padding(20 * u)

            if cc.outputExpanded {
                VStack(spacing: 4 * u) {
                    ForEach(Array(cc.outputs.enumerated()), id: \.element.id) { i, d in
                        let rowFocused = i == cc.outputFocus
                        HStack(spacing: 14 * u) {
                            Image(systemName: d.symbol).frame(width: 30 * u)
                            Text(d.name).lineLimit(1)
                            Spacer()
                            if d.id == cc.currentOutput { Image(systemName: "checkmark").fontWeight(.bold) }
                        }
                        .font(.system(size: 19 * u, weight: .medium))
                        .foregroundStyle(rowFocused ? .black : .white)
                        .padding(.horizontal, 16 * u)
                        .padding(.vertical, 12 * u)
                        .background(rowFocused ? .white : .clear, in: RoundedRectangle(cornerRadius: 16 * u, style: .continuous))
                        .scaleEffect(rowFocused ? 1.02 : 1)
                        .onTapGesture {
                            cc.outputFocus = i
                            _ = cc.handle(.select)
                        }
                    }
                }
                .padding([.horizontal, .bottom], 10 * u)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tile(focused: focused, u: u, expanded: cc.outputExpanded)
        .onTapGesture { cc.focus = .output; _ = cc.handle(.select) }
    }

    private func networkCard(_ u: CGFloat) -> some View {
        let n = cc.network
        return HStack(spacing: 14 * u) {
            Image(systemName: n.symbol, variableValue: n.bars.map { Double($0) / 3 } ?? 1)
                .font(.system(size: 24 * u, weight: .semibold))
                .foregroundStyle(n.kind == .offline ? .red : .green)
                .frame(width: 34 * u)
            VStack(alignment: .leading, spacing: 2 * u) {
                Text(n.title).font(.system(size: 19 * u, weight: .semibold))
                Text(networkDetail(n)).font(.system(size: 15 * u, weight: .medium)).opacity(0.6).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20 * u)
        .padding(.vertical, 16 * u)
        .glassSurface(RoundedRectangle(cornerRadius: 28 * u, style: .continuous))
    }

    private func networkDetail(_ n: NetworkInfo) -> String {
        guard n.kind != .offline else { return "Check your network connection" }
        var parts = ["Connected"]
        if let a = n.address { parts.append(a) }
        if let rssi = n.rssi, rssi != 0 { parts.append("\(rssi) dBm") }
        if n.vpn { parts.append("VPN") }
        if let i = n.interface { parts.append(i) }
        return parts.joined(separator: " · ")
    }
}

private extension View {
    /// tvOS Control Center focus: the focused tile turns to bright glass with dark content and lifts.
    func tile(focused: Bool, u: CGFloat, expanded: Bool = false) -> some View {
        self
            .foregroundStyle(focused ? .black : .white)
            .glassSurface(RoundedRectangle(cornerRadius: 28 * u, style: .continuous),
                          tint: focused ? .white.opacity(0.92) : expanded ? .white.opacity(0.08) : nil, interactive: true)
            .scaleEffect(focused ? 1.04 : 1)
            .shadow(color: .black.opacity(focused ? 0.3 : 0), radius: 16 * u, y: 8 * u)
            .zIndex(focused ? 1 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.2), value: focused)
    }
}
