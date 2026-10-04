import Foundation
import LGTV
import SwiftUI

/// What each page of the in-launcher settings contains. Built fresh from the current settings
/// every time it's drawn, so a row always shows the truth.
extension AppModel {
    func settingsRows(for page: SettingsScreen.Page) -> [SettingsRow] {
        switch page {
        case .homeScreen: homeScreenRows
        case .apps: settingsScreen.app.flatMap(appRows(for:)) ?? appRows
        case .adBlocking: adBlockingRows
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
            toggle("hints", "Control Hints", \.showHints, detail: "Button tips on the Home Screen, the app switcher, Settings and the keyboard"),
        ]
    }

    private var appRows: [SettingsRow] {
        settings.services.map { s in
            let shown = !settings.hidden.contains(s.id)
            return SettingsRow(
                id: s.id, title: s.name, detail: s.url.host(), style: .app(s, shown: shown),
                adjust: { [unowned self] in move(s.id, by: $0) },
                activate: { [unowned self] in settingsScreen.show(app: s.id) })
        } + [
            SettingsRow(id: "apps-note", title: "Click an app for its settings. Press ◀ or ▶ to move it along the Home Screen. Names, addresses and colors are in Settings on the Mac (⌘,).",
                        style: .note),
        ]
    }

    /// One app's own settings: whether it's on the Home Screen, the extensions that work on it, and
    /// how the remote gets around it. Nil if the app is gone.
    private func appRows(for id: String) -> [SettingsRow]? {
        guard let i = settings.services.firstIndex(where: { $0.id == id }) else { return nil }
        let s = settings.services[i]
        let shown = !settings.hidden.contains(s.id)
        var rows = [
            SettingsRow(id: "app-shown", title: "Show on Home Screen", style: .toggle(shown),
                        activate: { [unowned self] in
                            if shown { settings.hidden.insert(s.id) } else { settings.hidden.remove(s.id) }
                        }),
        ]

        let blocks = extensions.applies(.uBlockOriginLite, to: s), skips = extensions.applies(.sponsorBlock, to: s)
        if blocks || skips { rows.append(SettingsRow(id: "app-extensions-header", title: "Extensions", style: .header)) }
        if blocks {
            rows.append(SettingsRow(id: "app-ads", title: "Block Ads", detail: "With uBlock Origin Lite. Its filters are under Ad Blocking.",
                                    style: .toggle(s.blocksAds), activate: { [unowned self] in settings.services[i].blocksAds.toggle() }))
        }
        if skips {
            rows.append(SettingsRow(id: "app-sponsors", title: "SponsorBlock", detail: "Skips sponsor segments, intros and the like",
                                    style: .toggle(s.skipsSponsors), activate: { [unowned self] in settings.services[i].skipsSponsors.toggle() }))
            rows.append(SettingsRow(id: "app-sponsors-settings", title: "SponsorBlock Settings",
                                    detail: "Which kinds of segments to skip, mute or mark, on the Mac",
                                    style: .button, activate: { [unowned self] in openMacSettings(at: .apps, app: s.id) }))
        }

        rows.append(SettingsRow(id: "nav-header", title: "Remote", style: .header))
        if ServiceModules.handlesNavigation(s) {
            rows.append(SettingsRow(id: "nav-mode", title: "Navigation", detail: "\(s.name) handles the remote itself",
                                    style: .value("Built In")))
        } else {
            let mode = { [unowned self] (step: Int) in settings.services[i].navigation = cycled(s.navigation, step) }
            rows.append(SettingsRow(id: "nav-mode", title: "Navigation", detail: s.navigation.detail,
                                    style: .value(s.navigation.title), adjust: mode, activate: { mode(1) }))
            if s.navigation == .cursor { rows += cursorRows(i) }
        }
        rows.append(SettingsRow(id: "app-mac", title: "Name, Address and Appearance", detail: "In Settings on the Mac (⌘,)",
                                style: .button, activate: { [unowned self] in openMacSettings(at: .apps, app: s.id) }))
        rows.append(SettingsRow(id: "app-note", title: "The app reloads when you change its extensions or navigation. Cursor settings apply straight away.",
                                style: .note))
        return rows
    }

    private func cursorRows(_ i: Int) -> [SettingsRow] {
        let c = settings.services[i].cursor
        let change = { [unowned self] (edit: (inout CursorSettings) -> Void) in edit(&settings.services[i].cursor) }
        let speed = { (id: String, title: String, key: WritableKeyPath<CursorSettings, Double>) in
            SettingsRow(id: id, title: title, style: .slider(c[keyPath: key], label: String(format: "%.1f×", CursorSettings.gain(c[keyPath: key]))),
                        adjust: { step in change { $0[keyPath: key] = min(max(($0[keyPath: key] + Double(step) * 0.1).rounded(toPlaces: 1), 0), 1) } })
        }
        // One way of moving it has to stay on.
        let flip = { (key: WritableKeyPath<CursorSettings, Bool>, other: WritableKeyPath<CursorSettings, Bool>) in
            { change { if !$0[keyPath: key] || $0[keyPath: other] { $0[keyPath: key].toggle() } } }
        }
        return [
            SettingsRow(id: "cursor-header", title: "Cursor", style: .header),
            SettingsRow(id: "cursor-touch", title: "Move with Touch", detail: "Slide a finger on the clickpad, like a trackpad",
                        style: .toggle(c.followsTouch), activate: flip(\.followsTouch, \.followsArrows)),
            speed("cursor-touch-speed", "Touch Speed", \.touchSpeed),
            SettingsRow(id: "cursor-arrows", title: "Move with the Clickpad", detail: "Click the ring to step, hold it to glide",
                        style: .toggle(c.followsArrows), activate: flip(\.followsArrows, \.followsTouch)),
            speed("cursor-arrow-speed", "Clickpad Speed", \.arrowSpeed),
            SettingsRow(id: "cursor-snapping", title: "Snapping", detail: "How strongly it’s drawn onto buttons",
                        style: .value(c.snapping.title), adjust: { step in change { $0.snapping = cycled($0.snapping, step) } },
                        activate: { change { $0.snapping = cycled($0.snapping, 1) } }),
            SettingsRow(id: "cursor-size", title: "Size", style: .value(c.size.title),
                        adjust: { step in change { $0.size = cycled($0.size, step) } },
                        activate: { change { $0.size = cycled($0.size, 1) } }),
            SettingsRow(id: "ring-header", title: "Ring Scrolling", style: .header),
            SettingsRow(id: "ring", title: "Circle the Ring to Scroll", detail: "Run a finger around the clickpad’s edge",
                        style: .toggle(c.ringScrolls), activate: { change { $0.ringScrolls.toggle() } }),
            SettingsRow(id: "ring-direction", title: "Turning Clockwise Scrolls", style: .value(c.scrollDirection.title),
                        adjust: { step in change { $0.scrollDirection = cycled($0.scrollDirection, step) } },
                        activate: { change { $0.scrollDirection = cycled($0.scrollDirection, 1) } }),
            speed("ring-speed", "Scroll Speed", \.scrollSpeed),
            SettingsRow(id: "ring-momentum", title: "Momentum", detail: "Keeps scrolling for a moment after a quick turn",
                        style: .toggle(c.scrollMomentum), activate: { change { $0.scrollMomentum.toggle() } }),
        ]
    }

    /// uBlock Origin Lite's status, a way to its own settings on the Mac, and a switch for each app it works on.
    private var adBlockingRows: [SettingsRow] {
        let e = BundledExtension.uBlockOriginLite
        let apps = settings.services.indices.filter { extensions.applies(e, to: settings.services[$0]) }
        return [
            SettingsRow(id: "\(e.id)-status", title: e.name, style: .value(extensions.status(e).summary)),
            SettingsRow(id: "\(e.id)-settings", title: "\(e.name) Settings", detail: "Filter lists, filtering modes and your own filters, on the Mac",
                        style: .button, activate: { [unowned self] in openMacSettings(at: .adBlocking) }),
            SettingsRow(id: "\(e.id)-header", title: "Block Ads In", style: .header),
        ] + apps.map { i in
            let s = settings.services[i]
            return SettingsRow(id: "\(e.id)-\(s.id)", title: s.name, style: .toggle(s.blocksAds),
                               activate: { [unowned self] in settings.services[i].blocksAds.toggle() })
        } + [
            SettingsRow(id: "\(e.id)-note", title: apps.isEmpty ? "It doesn’t work on any of your apps." : "An app reloads when you change this.",
                        style: .note),
        ]
    }

    private var sleepModeRows: [SettingsRow] {
        [
            SettingsRow(id: "sleep", title: "Sleep Mode", detail: "Dims the screen and filters blue light",
                        style: .toggle(sleepMode), activate: { [unowned self] in toggleSleepMode() }),
            SettingsRow(id: "dim", title: "Dimming", style: .slider(settings.sleepDim / LauncherSettings.maxSleepDim, label: percent(settings.sleepDim)),
                        adjust: { [unowned self] in
                            settings.sleepDim = min(max((settings.sleepDim + Double($0) * 0.1).rounded(toPlaces: 1), 0), LauncherSettings.maxSleepDim)
                        }),
            SettingsRow(id: "warmth", title: "Blue Light Filter",
                        style: .slider(settings.sleepWarmth, label: percent(settings.sleepWarmth)),
                        adjust: { [unowned self] in
                            settings.sleepWarmth = min(max((settings.sleepWarmth + Double($0) * 0.1).rounded(toPlaces: 1), 0), 1)
                        }),
            toggle("sleep-cc", "Show in Control Center", \.sleepInControlCenter,
                   detail: "Adds a Sleep Mode tile to Control Center"),
            SettingsRow(id: "sleep-note", title: "Sleep Mode turns off when Lazybones quits.", style: .note),
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
        rows.append(SettingsRow(id: "tv-note", title: "Pairing shows a prompt on the TV; accept it with the TV’s remote. The TV needs “LG Connect Apps” or “Mobile TV On” turned on.",
                                style: .note))
        return rows
    }

    private var generalRows: [SettingsRow] {
        [
            toggle("fullscreen", "Open in Full Screen", \.startFullScreen, detail: "Takes effect the next time Lazybones opens"),
            toggle("sounds", "Navigation Sounds", \.navigationSounds, detail: "A soft tone when focus moves, and a brighter one when you select"),
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
        // The row slides into its new place, carrying focus with it.
        withAnimation(Motion.expand) {
            settings.services.swapAt(i, j)
            settingsScreen.focus(row: j)
        }
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

/// The next (or previous) of an enum's cases, round and round.
private func cycled<T: CaseIterable & Equatable>(_ value: T, _ step: Int) -> T {
    let all = Array(T.allCases)
    let i = all.firstIndex(of: value) ?? 0
    return all[(i + step % all.count + all.count) % all.count]
}
