import Foundation
import LGTV
import MacSystem

/// Everything the user can configure about the launcher. Saved by `SettingsStore`.
struct LauncherSettings: Codable, Equatable {
    /// All apps in Home Screen order, visible or not.
    var services = Service.defaults
    var hidden: Set<String> = []
    var columns = 5
    var showShelf = true
    /// Slow drifting light in the top shelf's artwork.
    var shelfMotion = true
    var showClock = true
    var homeMotion = HomeMotion.lively
    var focusSize = FocusSize.medium
    var iconLabels = IconLabels.focused
    /// Button tips on the Home Screen, the app switcher, Settings and the keyboard. Off by default,
    /// as on tvOS; for learning the remote.
    var showHints = false
    var showDebugOnLaunch = false
    var startFullScreen = true
    /// Play a sound when focus moves and when a choice is made.
    var navigationSounds = true
    var tv: TVConfig?
    /// Send volume to the paired TV when audio goes out over HDMI.
    var tvVolume = true
    /// Show the on-screen keyboard when a text field in a page is focused.
    var keyboard = true
    var keyboardLayout = KeyboardLayout.abc
    /// Sleep Mode: how far it dims the screen (0...`maxSleepDim`) and how much blue light it filters (0...1).
    var sleepDim = 0.4
    var sleepWarmth = 0.6
    /// Whether Sleep Mode sets the keyboard backlight on Macs that have one, and to how bright (0...1).
    var sleepSetsKeyboardLight = false
    var sleepKeyboardLight = 0.0
    /// Put a Sleep Mode tile in Control Center.
    var sleepInControlCenter = false

    var visibleServices: [Service] { services.filter { !hidden.contains($0.id) } }

    /// The darkest Sleep Mode goes: about a seventh of normal brightness.
    static let maxSleepDim = 0.9

    var sleepLevel: ScreenTint.Level { ScreenTint.Level(dim: sleepDim, warmth: sleepWarmth) }
    /// The keyboard backlight level Sleep Mode sets, or nil if it leaves the backlight alone.
    var sleepKeyboardLevel: Double? { sleepSetsKeyboardLight ? sleepKeyboardLight : nil }

    init() {}

    // Field by field, so settings saved by an older build still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LauncherSettings()
        services = try c.decodeIfPresent([Service].self, forKey: .services) ?? d.services
        hidden = try c.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? d.hidden
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? d.columns
        showShelf = try c.decodeIfPresent(Bool.self, forKey: .showShelf) ?? d.showShelf
        shelfMotion = try c.decodeIfPresent(Bool.self, forKey: .shelfMotion) ?? d.shelfMotion
        showClock = try c.decodeIfPresent(Bool.self, forKey: .showClock) ?? d.showClock
        homeMotion = (try? c.decodeIfPresent(HomeMotion.self, forKey: .homeMotion)) ?? d.homeMotion
        focusSize = (try? c.decodeIfPresent(FocusSize.self, forKey: .focusSize)) ?? d.focusSize
        iconLabels = (try? c.decodeIfPresent(IconLabels.self, forKey: .iconLabels)) ?? d.iconLabels
        showHints = try c.decodeIfPresent(Bool.self, forKey: .showHints) ?? d.showHints
        showDebugOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showDebugOnLaunch) ?? d.showDebugOnLaunch
        startFullScreen = try c.decodeIfPresent(Bool.self, forKey: .startFullScreen) ?? d.startFullScreen
        navigationSounds = try c.decodeIfPresent(Bool.self, forKey: .navigationSounds) ?? d.navigationSounds
        tv = try c.decodeIfPresent(TVConfig.self, forKey: .tv)
        tvVolume = try c.decodeIfPresent(Bool.self, forKey: .tvVolume) ?? d.tvVolume
        keyboard = try c.decodeIfPresent(Bool.self, forKey: .keyboard) ?? d.keyboard
        keyboardLayout = try c.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout) ?? d.keyboardLayout
        sleepDim = try c.decodeIfPresent(Double.self, forKey: .sleepDim) ?? d.sleepDim
        sleepWarmth = try c.decodeIfPresent(Double.self, forKey: .sleepWarmth) ?? d.sleepWarmth
        sleepSetsKeyboardLight = try c.decodeIfPresent(Bool.self, forKey: .sleepSetsKeyboardLight) ?? d.sleepSetsKeyboardLight
        sleepKeyboardLight = try c.decodeIfPresent(Double.self, forKey: .sleepKeyboardLight) ?? d.sleepKeyboardLight
        sleepInControlCenter = try c.decodeIfPresent(Bool.self, forKey: .sleepInControlCenter) ?? d.sleepInControlCenter
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
