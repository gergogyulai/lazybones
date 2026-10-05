import SwiftUI

// What every pane of the Mac's Settings window (⌘,) is built from, after System Settings: a
// colored icon for each pane in the sidebar, and a card at the top of the pane with a larger
// icon, its name and what it's for. The panes are the same as on the TV, in the same order.

extension SettingsScreen.Page {
    /// The color of the pane's icon.
    var color: Color {
        switch self {
        case .homeScreen: .blue
        case .apps: .orange
        case .adBlocking: .red
        case .sleepMode: .indigo
        case .keyboard: .gray
        case .tv: .teal
        case .general: .gray
        case .about: .gray
        }
    }

    /// The line under the pane's name at the top of the pane.
    var summary: String {
        switch self {
        case .homeScreen: "Arrange the app grid and choose what appears above it."
        case .apps: "Choose which apps are on the Home Screen and in what order, add any website as an app, and set up each app on its own."
        case .adBlocking: "Block ads, trackers and other clutter with uBlock Origin Lite."
        case .sleepMode: "Dim the screen and filter out blue light for watching late at night."
        case .keyboard: "The on-screen keyboard that appears when a page’s text field is selected."
        case .tv: "Control an LG TV’s volume and power over the network, since Macs can’t send HDMI-CEC."
        case .general: "Startup, sounds and troubleshooting."
        case .about: "This build of Lazybones, the Mac it’s running on, and where to report a problem."
        }
    }

    /// What else finds this pane from the search field, besides its name.
    var keywords: [String] {
        switch self {
        case .homeScreen: ["grid", "columns", "row", "top shelf", "hints", "layout"]
        case .apps: ["netflix", "youtube", "order", "hide", "show", "add", "website", "url", "color", "symbol",
                      "navigation", "remote", "cursor", "pointer", "mouse", "focus", "spatial", "arrow keys", "touch", "snapping", "scroll", "ring", "speed",
                      "sponsorblock", "sponsor", "skip", "segments", "intro", "outro"]
        case .adBlocking: ["ads", "adblock", "ublock", "origin", "lite", "filters", "content blocker", "youtube",
                            "level", "trackers", "privacy", "cookies", "consent", "pop-ups", "popups", "notifications", "chat", "social", "ai", "annoyances"]
        case .sleepMode: ["dim", "brightness", "blue light", "night", "warm", "keyboard", "backlight", "control center"]
        case .keyboard: ["text", "typing", "qwerty", "abc", "suggestions", "history", "search"]
        case .tv: ["lg", "webos", "volume", "power", "pair", "hdmi", "soundbar"]
        case .general: ["full screen", "sounds", "debug", "startup"]
        case .about: ["version", "build", "macos", "safari", "source", "github", "issue", "bug", "license"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || title.localizedCaseInsensitiveContains(q) || keywords.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

/// A pane's icon: a white symbol on a rounded square of the pane's color, lit from above like
/// the icons in System Settings.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: size * 0.03, y: size * 0.015)
            .frame(width: size, height: size)
            .background(color.gradient, in: shape)
            // The glassy sheen across the top half.
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)],
                                               startPoint: .top, endPoint: .center)))
            .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, size * 0.012)))
            .shadow(color: .black.opacity(0.12), radius: size * 0.05, y: size * 0.025)
            .accessibilityHidden(true)
    }
}

extension SettingsIcon {
    init(_ page: SettingsScreen.Page, size: CGFloat = 20) {
        self.init(symbol: page.symbol, color: page.color, size: size)
    }
}

/// A pane: its heading card, then its sections, in a grouped form.
struct SettingsPane<Content: View>: View {
    let page: SettingsScreen.Page
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    SettingsIcon(page, size: 60)
                        .padding(.bottom, 4)
                    Text(page.title)
                        .font(.title2.weight(.semibold))
                    Text(page.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
            content
        }
        .formStyle(.grouped)
        .navigationTitle(page.title)
    }
}
