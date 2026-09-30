import AppKit
import SwiftUI

struct DebugOverlay: View {
    @EnvironmentObject var diagnostics: Diagnostics
    /// The open service, whose reports are listed.
    let service: Service?
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
            if let s = service {
                let r = diagnostics.reports[s.id] ?? [:]
                Text(s.name).bold().padding(.top, 4)
                ForEach(r.keys.sorted { rank($0) < rank($1) }, id: \.self) { k in
                    Text("\(k): \(r[k]!)").lineLimit(2).foregroundStyle(color(k, r[k]!))
                }
            }
            Divider().padding(.vertical, 4)
            ForEach(Array(diagnostics.events.suffix(6).enumerated()), id: \.offset) { _, e in
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
        let s = diagnostics.remote
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
