import Combine
import LGTV
import SiriRemote
import SwiftUI

/// One line in the in-launcher settings.
struct SettingsRow: Identifiable {
    enum Style {
        case toggle(Bool)
        /// A fraction of the bar filled (0...1) and the value it stands for.
        case slider(Double, label: String)
        case value(String)
        case button
        case app(Service, shown: Bool)
        /// Text that isn't a setting: a heading, or a note about the settings above.
        case header
        case note
    }

    let id: String
    var title: String
    var detail: String?
    var style: Style
    /// Left (-1) and right (+1) on the remote.
    var adjust: ((Int) -> Void)?
    /// Click.
    var activate: (() -> Void)?

    /// Rows that only show something can't take focus.
    var focusable: Bool { adjust != nil || activate != nil }
}

/// The settings screen you reach from the Home Screen or Control Center, driven by the remote.
/// The Mac's Settings window (⌘,) stays for what needs a keyboard: names, addresses and colors.
///
/// This holds where focus is; the rows themselves come from `rows`, so they always show the
/// current settings.
@MainActor
final class SettingsScreen: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case homeScreen, apps, sleepMode, keyboard, tv, general

        var id: String { rawValue }

        var title: String {
            switch self {
            case .homeScreen: "Home Screen"
            case .apps: "Apps"
            case .sleepMode: "Sleep Mode"
            case .keyboard: "Keyboard"
            case .tv: "TV"
            case .general: "General"
            }
        }

        var symbol: String {
            switch self {
            case .homeScreen: "rectangle.grid.3x2.fill"
            case .apps: "square.grid.2x2.fill"
            case .sleepMode: "moon.zzz.fill"
            case .keyboard: "keyboard.fill"
            case .tv: "tv.fill"
            case .general: "gearshape.fill"
            }
        }
    }

    @Published private(set) var isOpen = false
    @Published private(set) var page = Page.homeScreen
    /// Index into the page's rows.
    @Published private(set) var row = 0
    /// Focus is in the list of pages rather than the rows.
    @Published private(set) var inSidebar = true

    /// Finds TVs while the TV page is showing.
    let discovery = TVDiscovery()
    /// The rows of a page. Set by whoever owns the settings.
    var rowsProvider: (Page) -> [SettingsRow] = { _ in [] }

    private var discoveryChanges: AnyCancellable?

    init() {
        discoveryChanges = discovery.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    var rows: [SettingsRow] { rowsProvider(page) }

    func open(page: Page? = nil) {
        if let page { self.page = page }
        row = 0
        inSidebar = true
        updateDiscovery()
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { isOpen = true }
    }

    func close() {
        discovery.stop()
        withAnimation(.easeOut(duration: 0.25)) { isOpen = false }
    }

    func select(page: Page) {
        guard page != self.page else { return }
        self.page = page
        row = 0
        updateDiscovery()
    }

    func handle(_ command: RemoteCommand) {
        let animation = Animation.spring(duration: 0.25, bounce: 0.2)
        if inSidebar {
            let pages = Page.allCases
            let i = pages.firstIndex(of: page) ?? 0
            switch command {
            case .up where i > 0: withAnimation(animation) { select(page: pages[i - 1]) }
            case .down where i < pages.count - 1: withAnimation(animation) { select(page: pages[i + 1]) }
            case .right, .select: enterRows()
            case .back: close()
            default: break
            }
            return
        }

        let rows = self.rows
        switch command {
        case .up: move(-1, in: rows)
        case .down: move(1, in: rows)
        case .left, .right:
            let step = command == .left ? -1 : 1
            if rows.indices.contains(row), let adjust = rows[row].adjust {
                adjust(step)
            } else if command == .left {
                withAnimation(animation) { inSidebar = true }
            }
        case .select:
            guard rows.indices.contains(row) else { break }
            if let activate = rows[row].activate { activate() } else { rows[row].adjust?(1) }
        case .back: withAnimation(animation) { inSidebar = true }
        default: break
        }
    }

    /// Clicking a row with the mouse or trackpad.
    func click(row i: Int) {
        let rows = self.rows
        guard rows.indices.contains(i), rows[i].focusable else { return }
        inSidebar = false
        row = i
        if let activate = rows[i].activate { activate() } else { rows[i].adjust?(1) }
    }

    /// Moves focus to a row, e.g. after the row's own action moved it.
    func focus(row i: Int) { row = i }

    private func enterRows() {
        guard let first = rows.firstIndex(where: \.focusable) else { return }
        withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
            inSidebar = false
            row = first
        }
    }

    /// Moves to the next row that can take focus, skipping rows that only show information.
    private func move(_ delta: Int, in rows: [SettingsRow]) {
        var i = row + delta
        while rows.indices.contains(i) {
            if rows[i].focusable {
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) { row = i }
                return
            }
            i += delta
        }
    }

    private func updateDiscovery() {
        if page == .tv { discovery.start() } else { discovery.stop() }
    }
}
