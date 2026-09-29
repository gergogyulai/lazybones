import Foundation
import LGTV

/// Everything the user can configure about the launcher. Saved by `SettingsStore`.
struct LauncherSettings: Codable, Equatable {
    /// All apps in Home Screen order, visible or not.
    var services = Service.defaults
    var hidden: Set<String> = []
    var columns = 5
    var showShelf = true
    var showHints = true
    var showDebugOnLaunch = false
    var startFullScreen = true
    var tv: TVConfig?
    /// Send volume to the paired TV when audio goes out over HDMI.
    var tvVolume = true
    /// Show the on-screen keyboard when a text field in a page is focused.
    var keyboard = true
    var keyboardLayout = KeyboardLayout.abc

    var visibleServices: [Service] { services.filter { !hidden.contains($0.id) } }

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

    /// Adds built-ins that came with a newer build, each after its predecessor in the default order.
    func mergingNewBuiltIns(from defaults: [Service] = Service.defaults) -> LauncherSettings {
        var s = self
        for (i, d) in defaults.enumerated() where !s.services.contains(where: { $0.id == d.id }) {
            let after = defaults[..<i].last { p in s.services.contains { $0.id == p.id } }
            let at = after.flatMap { p in s.services.firstIndex { $0.id == p.id } }.map { $0 + 1 } ?? 0
            s.services.insert(d, at: at)
        }
        return s
    }
}
