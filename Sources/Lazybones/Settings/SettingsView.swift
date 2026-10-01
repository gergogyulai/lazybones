import AppKit
import SwiftUI

/// The Mac's Settings window (⌘,), laid out like System Settings: the panes in a sidebar, which
/// macOS 26 floats as Liquid Glass, with a search field to find a setting by name, and back and
/// forward buttons beside the pane's name in the toolbar.
struct SettingsView: View {
    static let windowID = "settings"
    /// Where the pane showing is remembered, which also opens the window at a given pane.
    static let paneKey = "settingsPane"

    @AppStorage(paneKey) private var pane = SettingsScreen.Page.homeScreen
    @State private var query = ""
    /// The panes visited before and after this one, for back and forward.
    @State private var back: [SettingsScreen.Page] = []
    @State private var forward: [SettingsScreen.Page] = []

    var body: some View {
        NavigationSplitView {
            let pages = SettingsScreen.Page.allCases.filter { $0.matches(query) }
            List(selection: Binding(get: { pane }, set: { if let p = $0 { go(to: p) } })) {
                ForEach(pages) { page in
                    Label {
                        Text(page.title)
                    } icon: {
                        SettingsIcon(page, size: 24)
                    }
                    .tag(page)
                }
            }
            .environment(\.sidebarRowSize, .large)
            .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)
            .searchable(text: $query, placement: .sidebar)
            // Searching jumps to the first pane that matches, as System Settings does.
            .onChange(of: query) {
                let matching = SettingsScreen.Page.allCases.filter { $0.matches(query) }
                if let first = matching.first, !matching.contains(pane) { go(to: first) }
            }
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(minWidth: 520)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            Button("Back", systemImage: "chevron.left", action: goBack)
                                .keyboardShortcut("[")
                                .disabled(back.isEmpty)
                            Button("Forward", systemImage: "chevron.right", action: goForward)
                                .keyboardShortcut("]")
                                .disabled(forward.isEmpty)
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(SettingsWindowBehavior())
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .homeScreen: HomeScreenSettings()
        case .apps: AppsSettings()
        case .adBlocking: AdBlockingSettings()
        case .sponsorBlock: SponsorBlockSettings()
        case .sleepMode: SleepSettings()
        case .keyboard: KeyboardSettings()
        case .tv: TVSettings()
        case .general: GeneralSettings()
        }
    }

    private func go(to page: SettingsScreen.Page) {
        guard page != pane else { return }
        back.append(pane)
        forward.removeAll()
        pane = page
    }

    private func goBack() {
        guard let page = back.popLast() else { return }
        forward.append(pane)
        pane = page
    }

    private func goForward() {
        guard let page = forward.popLast() else { return }
        back.append(pane)
        pane = page
    }
}

/// Settings… in the app menu, with ⌘,.
struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") { openWindow(id: SettingsView.windowID) }
            .keyboardShortcut(",")
    }
}

/// Makes a utility window (Settings, About) behave like a Settings window: it opens over the launcher when that's full
/// screen, on whichever Space is showing, instead of taking a full-screen Space of its own.
struct SettingsWindowBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowWatcher() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowWatcher: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.collectionBehavior = [.fullScreenAuxiliary, .fullScreenNone, .moveToActiveSpace]
        }
    }
}
