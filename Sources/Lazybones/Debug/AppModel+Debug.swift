import Foundation
import SiriRemote

/// What the debug window's State tab and `Scripts/ctl.sh state` show, and `ctl.sh`'s commands.
extension AppModel {
    /// What the app is showing and doing right now, as label/value rows.
    var debugState: [(String, String)] {
        var rows: [(String, String)] = []
        var screen = active?.name ?? "Home"
        if let p = presented, p.id != active?.id { screen += " (\(p.name) zooming back)" }
        rows.append(("screen", screen))
        if active == nil {
            let app = visible.indices.contains(focus.index) ? visible[focus.index].name : "none"
            rows.append(("focus", focus.onBar ? "top bar" : "\(app) (#\(focus.index), column \(focus.column))"))
        }
        var overlays: [String] = []
        if controlCenter.isOpen { overlays.append("Control Center (\(controlCenter.focus))") }
        if settingsScreen.isOpen {
            overlays.append("Settings (\(settingsScreen.page.rawValue), \(settingsScreen.inSidebar ? "sidebar" : "row \(settingsScreen.row)"))")
        }
        if switcher.isOpen { overlays.append("App Switcher (\(switcher.focus))") }
        if keyboard.isVisible { overlays.append("keyboard (\(keyboard.field.map { "\($0.kind)" } ?? "no field"))") }
        if showsFailure { overlays.append("failure screen") }
        rows.append(("overlays", overlays.isEmpty ? "none" : overlays.joined(separator: ", ")))
        if cursor.serviceID != nil {
            let a = cursor.appearance
            rows.append(("cursor", "\(a.visible ? "shown" : "hidden") at \(Int(a.point.x)),\(Int(a.point.y))"
                             + (a.morph > 0.5 ? " on \(Int(a.highlight.width))×\(Int(a.highlight.height))" : "")
                             + (cursorTakesTouch ? ", following touch" : "")
                             + ", page at \(Int(a.page.minX)),\(Int(a.page.minY)) \(Int(a.page.width))×\(Int(a.page.height))"))
        }

        for (id, wv) in web.views.sorted(by: { $0.key < $1.key }) {
            var flags: [String] = []
            if mounted.contains(where: { $0.id == id }) { flags.append("mounted") }
            if playing.contains(id) { flags.append("playing") }
            if loading.contains(id) { flags.append("loading") }
            if let f = failures[id] { flags.append("failed: \(f.reason)") }
            if let c = diagnostics.consoleCounts[id], c.errors + c.warnings > 0 {
                flags.append("\(c.errors) errors, \(c.warnings) warnings")
            }
            let tags = flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"
            rows.append(("page \(id)", (wv.url?.absoluteString ?? "no URL") + tags))
        }

        rows.append(("sleep mode", sleepMode ? "on (\(settings.sleepLevel))" : "off"))
        let r = diagnostics.remote
        var remoteLine = "buttons \(r.buttons), touch \(r.touch ? "on" : "off")"
        if let b = r.battery { remoteLine += ", battery \(b.percent)%\(b.charging ? " charging" : "")" }
        rows.append(("remote", remoteLine))
        rows.append(("tv", settings.tv == nil ? "not paired" : "\(tv.name): \(tv.status)"))
        if let v = volume.router.state() {
            rows.append(("volume", "\(v.level)%\(v.muted ? " muted" : "") on \(v.target)"))
        } else {
            rows.append(("volume", "unknown"))
        }
        let n = controlCenter.network
        rows.append(("network", "\(n.kind)" + (n.interface.map { " on \($0)" } ?? "") + (n.address.map { ", \($0)" } ?? "")
                         + (n.vpn ? ", VPN" : "")))
        return rows
    }

    /// Runs a command from `Scripts/ctl.sh` and says what came of it.
    func run(_ command: DevCommand) async -> String {
        diagnostics.log("\(command)", .control, level: .debug)
        switch command {
        case let .press(buttons, hold):
            await send(buttons.map { RemoteEvent(command: $0, source: hold ? .hold : .press) })
            return debugStateText
        case let .swipe(directions):
            await send(directions.map { RemoteEvent(command: $0, source: .swipe) })
            return debugStateText
        case let .drag(dx, dy):
            let from = SIMD2<Float>(0.5, 0.5)
            await touchPath { from + SIMD2(dx, dy) * $0 }
            return debugStateText
        case let .turn(degrees):
            // Clockwise from the top of the ring, with y up.
            await touchPath { t in
                let a = Float.pi / 2 - degrees * .pi / 180 * t
                return SIMD2(0.5 + 0.4 * cos(a), 0.5 + 0.4 * sin(a))
            }
            return debugStateText
        case let .open(id):
            guard let s = settings.services.first(where: { $0.id == id || $0.name.lowercased() == id.lowercased() }) else {
                return "error: no service \(id). Known: \(settings.services.map(\.id).joined(separator: ", "))"
            }
            open(s)
            return "opened \(s.name)"
        case let .eval(js, id):
            guard let id = id ?? active?.id else { return "error: no app is open; name one with eval @<id> ..." }
            return await web.evaluate(js, in: id)
        case .state:
            return debugStateText
        case let .log(lines):
            return diagnostics.events.suffix(lines).map(\.line).joined(separator: "\n")
        case .settings:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return (try? encoder.encode(settings)).flatMap { String(data: $0, encoding: .utf8) } ?? "error: couldn't encode settings"
        case .reload:
            guard active != nil else { return "error: no app is open" }
            reload()
            return "reloaded"
        case .overlay:
            diagnostics.toggle()
            return "overlay \(diagnostics.isVisible ? "on" : "off")"
        case .window:
            openDebugWindow()
            return "opened the debug window"
        }
    }

    /// Through the on-screen remote, which lights the buttons, at about the pace of a quick thumb.
    /// Waits after the last too, so the state reported afterwards includes it.
    private func send(_ events: [RemoteEvent]) async {
        for e in events {
            simulator.inject(e)
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    /// A finger along `path` (0...1 in, a point on the touch surface out), over a third of a second.
    private func touchPath(_ path: (Float) -> SIMD2<Float>) async {
        let steps = 40
        simulator.touch(.began, at: path(0))
        for i in 1...steps {
            try? await Task.sleep(for: .milliseconds(8))
            simulator.touch(.moved, at: path(Float(i) / Float(steps)))
        }
        // Still for a moment before lifting, so a turn doesn't carry on with momentum.
        try? await Task.sleep(for: .milliseconds(120))
        simulator.touch(.ended, at: path(1))
        try? await Task.sleep(for: .milliseconds(300))
    }

    var debugStateText: String {
        let rows = debugState
        let width = rows.map(\.0.count).max() ?? 0
        return rows.map { $0.0.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + $0.1 }.joined(separator: "\n")
    }

    /// Everything worth attaching to a bug report: state, what pages reported, and the log.
    var debugReport: String {
        var out = "Lazybones \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")"
        out += " · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"
        out += debugStateText + "\n"
        for (id, report) in diagnostics.reports.sorted(by: { $0.key < $1.key }) {
            out += "\n\(id)\n"
            for (k, v) in report.sorted(by: { $0.key < $1.key }) { out += "  \(k): \(v)\n" }
        }
        out += "\nlog\n" + diagnostics.events.map(\.line).joined(separator: "\n") + "\n"
        return out
    }
}
