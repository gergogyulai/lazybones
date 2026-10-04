import Foundation
import WebKit

/// The few of uBlock Origin Lite's settings worth having at hand, in plain words: how hard it
/// filters, and which kinds of clutter it blocks besides ads. Everything else is on its own
/// settings page. The settings stay uBO Lite's, so they show there too, and apply to every app
/// that blocks ads.
@MainActor
final class AdBlockOptions: ObservableObject {
    /// uBO Lite's default filtering mode, without "no filtering", which the switch for each app covers.
    enum Level: Int, CaseIterable, Identifiable {
        case basic = 1, optimal, complete

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .basic: "Basic"
            case .optimal: "Standard"
            case .complete: "Thorough"
            }
        }

        var detail: String {
            switch self {
            case .basic: "Blocks ads from loading, but can leave empty spaces where they were. Least likely to break a site."
            case .optimal: "Also cleans up what’s left and stops ad scripts, site by site. Recommended."
            case .complete: "Also hides anything that looks like an ad on every site. Catches the most, but more likely to hide something it shouldn’t."
            }
        }
    }

    /// Filter lists that block something besides ads, by uBO Lite's id for them.
    enum Extra: String, CaseIterable, Identifiable {
        case trackers = "easyprivacy"
        case cookieBanners = "annoyances-cookies"
        case overlays = "annoyances-overlays"
        case notificationPrompts = "annoyances-notifications"
        case chatBubbles = "annoyances-widgets"
        case socialButtons = "annoyances-social"
        case aiWidgets = "annoyances-ai"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trackers: "Trackers"
            case .cookieBanners: "Cookie Banners"
            case .overlays: "Pop-Up Boxes"
            case .notificationPrompts: "Notification Requests"
            case .chatBubbles: "Chat Bubbles"
            case .socialButtons: "Social Media Buttons"
            case .aiWidgets: "AI Assistants"
            }
        }

        var detail: String {
            switch self {
            case .trackers: "Scripts that follow what you watch across sites"
            case .cookieBanners: "Cookie consent notices"
            case .overlays: "Newsletter sign-ups and other boxes that cover the page"
            case .notificationPrompts: "Sites asking to send you notifications"
            case .chatBubbles: "Support and sales chat windows"
            case .socialButtons: "Share and like buttons, and embedded posts"
            case .aiWidgets: "Chatbots and AI summaries built into sites"
            }
        }
    }

    /// Nil until uBO Lite has said, and if it never loads.
    @Published private(set) var level: Level?
    @Published private(set) var enabled: Set<String> = []

    var onStatus: ((String) -> Void)?
    private var context: WKWebExtensionContext?
    private let page: ExtensionPage
    /// The latest change, which each waits for, so they reach uBO Lite in order.
    private var changing: Task<Void, Never>?

    init(page: ExtensionPage) { self.page = page }

    func isOn(_ extra: Extra) -> Bool { enabled.contains(extra.rawValue) }

    /// Reads the settings from the loaded extension, as after they were changed on its own page.
    func refresh(in context: WKWebExtensionContext? = nil) async {
        if let context { self.context = context }
        await perform("read its settings", """
        const [level, enabled] = await Promise.all([
          send({ what: 'getDefaultFilteringMode' }),
          send({ what: 'getEnabledRulesets' }),
        ]);
        return { level, enabled };
        """)
    }

    func set(_ level: Level) {
        self.level = level
        change("set the blocking level", """
        await send({ what: 'setDefaultFilteringMode', level: \(level.rawValue) });
        """)
    }

    func set(_ extra: Extra, on: Bool) {
        if on { enabled.insert(extra.rawValue) } else { enabled.remove(extra.rawValue) }
        change("turn \(on ? "on" : "off") \(extra.rawValue)", """
        const enabled = new Set(await send({ what: 'getEnabledRulesets' }));
        if (on) enabled.add(id); else enabled.delete(id);
        await send({ what: 'applyRulesets', enabledRulesets: Array.from(enabled) });
        """, arguments: ["id": extra.rawValue, "on": on])
    }

    /// Runs `js`, then reads the settings back, so they show what uBO Lite actually did.
    private func change(_ what: String, _ js: String, arguments: [String: Any] = [:]) {
        let previous = changing
        changing = Task {
            await previous?.value
            await perform(what, js + """

            return {
              level: await send({ what: 'getDefaultFilteringMode' }),
              enabled: await send({ what: 'getEnabledRulesets' }),
            };
            """, arguments: arguments)
        }
    }

    private func perform(_ what: String, _ js: String, arguments: [String: Any] = [:]) async {
        guard let context else { return }
        do {
            let result = try await page.run(js, arguments: arguments, in: context) as? [String: Any]
            level = (result?["level"] as? Int).flatMap(Level.init(rawValue:))
            enabled = Set(result?["enabled"] as? [String] ?? [])
            onStatus?("uBO Lite: \(level?.title ?? "no") filtering, lists \(enabled.sorted().joined(separator: ", "))")
        } catch {
            onStatus?("uBO Lite: couldn’t \(what): \(error.localizedDescription)")
        }
    }
}
