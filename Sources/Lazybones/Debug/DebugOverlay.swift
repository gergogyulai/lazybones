import AppKit
import SwiftUI

/// A glanceable panel over whatever's on screen: what the app is doing, what the open page reports
/// about itself, and the latest log lines. The debug window (⌥⌘D) has the rest.
struct DebugOverlay: View {
    @EnvironmentObject var diagnostics: Diagnostics
    @EnvironmentObject var model: AppModel
    /// The open service, whose reports are listed.
    let service: Service?
    private let order = ["page", "load", "display", "MSE", "EME FairPlay", "EME Widevine", "encrypted",
                              "video", "codec", "HDR", "audio", "DRM", "video error", "play/pause"]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(remoteSummary).foregroundStyle(.secondary)
            ForEach(model.debugState.filter { ["screen", "focus", "overlays"].contains($0.0) }, id: \.0) { k, v in
                Text("\(k): \(v)").lineLimit(1).foregroundStyle(.secondary)
            }
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
                HStack {
                    Text(s.name).bold()
                    if let c = diagnostics.consoleCounts[s.id], c.errors + c.warnings > 0 {
                        Text("console: \(c.errors) errors, \(c.warnings) warnings")
                            .foregroundStyle(c.errors > 0 ? .red : .orange)
                    }
                }
                .padding(.top, 4)
                ForEach(r.keys.sorted { rank($0) < rank($1) }, id: \.self) { k in
                    Text("\(k): \(r[k]!)").lineLimit(2).foregroundStyle(color(k, r[k]!))
                }
            }
            Divider().padding(.vertical, 4)
            ForEach(diagnostics.events.suffix(8)) { e in
                Text("\(e.time.prefix(8)) \(e.category.rawValue) \(e.message)")
                    .foregroundStyle(e.level.color)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 440, alignment: .leading)
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

extension LogLevel {
    /// How the overlay and the debug window color an entry.
    var color: Color {
        switch self {
        case .debug: .gray
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
