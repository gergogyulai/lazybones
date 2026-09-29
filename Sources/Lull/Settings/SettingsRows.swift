import Foundation
import LGTV

/// What each page of the in-launcher settings contains. Built fresh from the current settings
/// every time it's drawn, so a row always shows the truth.
extension AppModel {
    func settingsRows(for page: SettingsScreen.Page) -> [SettingsRow] {
        switch page {
        case .homeScreen: homeScreenRows
        case .apps: appRows
        case .sleepMode: sleepModeRows
        case .keyboard: keyboardRows
        case .tv: tvRows
        case .general: generalRows
        }
    }

    // MARK: Pages

    private var homeScreenRows: [SettingsRow] {
        [
            SettingsRow(id: "columns", title: "Apps per Row", style: .value("\(settings.columns)"),
                        adjust: { [unowned self] in settings.columns = min(max(settings.columns + $0, 3), 7) },
                        activate: { [unowned self] in settings.columns = settings.columns >= 7 ? 3 : settings.columns + 1 }),
            toggle("shelf", "Top Shelf", \.showShelf, detail: "Big artwork above the apps for the focused app"),
            toggle("hints", "Control Hints", \.showHints, detail: "The line of button tips at the top of the Home Screen"),
        ]
    }

    private var appRows: [SettingsRow] {
        settings.services.map { s in
            let shown = !settings.hidden.contains(s.id)
            return SettingsRow(
                id: s.id, title: s.name, detail: s.url.host(), style: .app(s, shown: shown),
                adjust: { [unowned self] in move(s.id, by: $0) },
                activate: { [unowned self] in
                    if shown { settings.hidden.insert(s.id) } else { settings.hidden.remove(s.id) }
                })
        } + [
            SettingsRow(id: "apps-note", title: "Click to show or hide an app. Press ◀ or ▶ to move it along the Home Screen. Names, addresses and colors are in Settings on the Mac (⌘,).",
                        style: .note),
        ]
    }

    private var sleepModeRows: [SettingsRow] {
        [
            SettingsRow(id: "sleep", title: "Sleep Mode", detail: "Dims the screen and filters blue light",
                        style: .toggle(sleepMode), activate: { [unowned self] in toggleSleepMode() }),
            SettingsRow(id: "dim", title: "Dimming", style: .slider(settings.sleepDim / 0.8, label: percent(settings.sleepDim)),
                        adjust: { [unowned self] in
                            settings.sleepDim = min(max((settings.sleepDim + Double($0) * 0.1).rounded(toPlaces: 1), 0), 0.8)
                        }),
            SettingsRow(id: "warmth", title: "Blue Light Filter",
                        style: .slider(settings.sleepWarmth, label: percent(settings.sleepWarmth)),
                        adjust: { [unowned self] in
                            settings.sleepWarmth = min(max((settings.sleepWarmth + Double($0) * 0.1).rounded(toPlaces: 1), 0), 1)
                        }),
            toggle("sleep-cc", "Show in Control Center", \.sleepInControlCenter,
                   detail: "Adds a Sleep Mode tile to Control Center"),
            SettingsRow(id: "sleep-note", title: "Sleep Mode turns off when Lull quits.", style: .note),
        ]
    }

    private var keyboardRows: [SettingsRow] {
        let flip = { [unowned self] in
            settings.keyboardLayout = settings.keyboardLayout == .abc ? .qwerty : .abc
        }
        return [
            toggle("keyboard", "Show on Text Fields", \.keyboard, detail: "Pops up when a text field on a page is selected"),
            SettingsRow(id: "layout", title: "Layout", style: .value(settings.keyboardLayout == .abc ? "ABC" : "QWERTY"),
                        adjust: { _ in flip() }, activate: flip),
            SettingsRow(id: "clear-history", title: "Clear Recent Searches and Emails", style: .button,
                        activate: { KeyboardHistory.clear() }),
            SettingsRow(id: "keyboard-note", title: "Sites in Smart TV mode use their own keyboard.", style: .note),
        ]
    }

    private var tvRows: [SettingsRow] {
        var rows: [SettingsRow] = []
        if let config = settings.tv {
            rows.append(SettingsRow(id: "tv", title: config.name, detail: config.host, style: .value(tv.status.summary)))
            rows.append(SettingsRow(id: "tv-reconnect", title: "Reconnect", style: .button, activate: { [unowned self] in tv.connect() }))
            rows.append(SettingsRow(id: "tv-forget", title: "Forget TV", style: .button, activate: { [unowned self] in settings.tv = nil }))
        }
        rows.append(toggle("tv-volume", "Control TV Volume", \.tvVolume,
                           detail: "Sends volume to the TV when audio goes out over HDMI"))
        rows.append(SettingsRow(id: "tv-found", title: "LG TVs on This Network", style: .header))
        let found = settingsScreen.discovery.found
        if found.isEmpty { rows.append(SettingsRow(id: "tv-searching", title: "Looking for LG TVs…", style: .note)) }
        for tvFound in found {
            let paired = settings.tv?.name == tvFound.name
            rows.append(SettingsRow(
                id: "tv-\(tvFound.id)", title: tvFound.name, style: .value(paired ? "Paired" : tvPairing == tvFound.name ? "Pairing…" : "Pair"),
                activate: paired ? nil : { [unowned self] in pair(tvFound) }))
        }
        if let tvPairError { rows.append(SettingsRow(id: "tv-error", title: tvPairError, style: .note)) }
        rows.append(SettingsRow(id: "tv-note", title: "Pairing shows a prompt on the TV; accept it with the TV's remote. The TV needs \"LG Connect Apps\" or \"Mobile TV On\" turned on.",
                                style: .note))
        return rows
    }

    private var generalRows: [SettingsRow] {
        [
            toggle("fullscreen", "Open in Full Screen", \.startFullScreen, detail: "Takes effect the next time Lull opens"),
            toggle("debug-launch", "Show Debug Overlay at Launch", \.showDebugOnLaunch),
            SettingsRow(id: "debug", title: "Debug Overlay", detail: "DRM, codecs and HDR for the open app",
                        style: .toggle(diagnostics.isVisible), activate: { [unowned self] in diagnostics.toggle() }),
            SettingsRow(id: "mac-settings", title: "Open Settings on the Mac", detail: "Names, addresses and colors of apps (⌘,)",
                        style: .button, activate: { [unowned self] in openMacSettings() }),
            SettingsRow(id: "version", title: "Version", style: .value(Self.version)),
        ]
    }

    // MARK: Helpers

    private func toggle(_ id: String, _ title: String, _ key: WritableKeyPath<LauncherSettings, Bool>,
                        detail: String? = nil) -> SettingsRow {
        SettingsRow(id: id, title: title, detail: detail, style: .toggle(settings[keyPath: key]),
                    activate: { [unowned self] in settings[keyPath: key].toggle() })
    }

    /// Moves an app along the Home Screen, and the focused row with it.
    private func move(_ id: String, by step: Int) {
        guard let i = settings.services.firstIndex(where: { $0.id == id }) else { return }
        let j = i + step
        guard settings.services.indices.contains(j) else { return }
        settings.services.swapAt(i, j)
        settingsScreen.focus(row: j)
    }

    private func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
