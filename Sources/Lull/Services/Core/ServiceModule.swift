import Foundation
import WebKit

/// Everything specific to one service: its Home Screen entry plus whatever scripts, styles and
/// WebKit tweaks its site needs. Each module lives in its own folder under Services/ and is only
/// ever applied to its own service's web view, so a hack for one site can't leak into another.
/// Everything is optional except the entry.
protocol ServiceModule: Sendable {
    /// The built-in Home Screen entry. Its `id` is how saved settings find the module again.
    var service: Service { get }
    /// The site does its own remote/keyboard navigation, so Lull's spatial navigation is never
    /// added, whatever the saved setting says.
    var handlesNavigation: Bool { get }
    /// Page scripts, injected after the shared ones in `Scripts`.
    var scripts: [PageScript] { get }
    /// CSS added to every page, e.g. to hide banners that make no sense on a TV.
    var styles: [String] { get }
    /// Whether going Home pauses the page's media. Music keeps playing instead, like Music on an
    /// Apple TV, and the remote's Play/Pause still reaches it from the Home Screen.
    var pausesInBackground: Bool { get }
    /// A script that toggles playback and returns what it did, for pages whose player is more than
    /// a bare media element. Without one, the largest video is played or paused.
    var playPauseScript: String? { get }
    /// The URL to load first, given the service as the user configured it.
    func startURL(for s: Service) -> URL
    /// Changes to the shared web view configuration, before the web view is created.
    @MainActor func configure(_ config: WKWebViewConfiguration, for s: Service)
    /// Changes to the new web view, before its first load.
    @MainActor func prepare(_ webView: WKWebView, for s: Service)
}

extension ServiceModule {
    var handlesNavigation: Bool { false }
    var scripts: [PageScript] { [] }
    var styles: [String] { [] }
    var pausesInBackground: Bool { true }
    var playPauseScript: String? { nil }
    func startURL(for s: Service) -> URL { s.url }
    @MainActor func configure(_ config: WKWebViewConfiguration, for s: Service) {}
    @MainActor func prepare(_ webView: WKWebView, for s: Service) {}
}

struct PageScript: Sendable {
    enum Time: Sendable { case start, end }

    var source: String
    var time = Time.end
    var mainFrameOnly = true

    @MainActor var userScript: WKUserScript {
        WKUserScript(source: source, injectionTime: time == .start ? .atDocumentStart : .atDocumentEnd,
                     forMainFrameOnly: mainFrameOnly)
    }

    /// Adds `css` to the page as early as it can.
    static func style(_ css: String) -> PageScript {
        let literal = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "''"
        return PageScript(source: """
        (() => {
          const add = () => {
            const s = document.createElement('style');
            s.textContent = \(literal);
            (document.head || document.documentElement).appendChild(s);
          };
          document.documentElement ? add() : addEventListener('DOMContentLoaded', add);
        })();
        """, time: .start, mainFrameOnly: false)
    }
}

enum ServiceModules {
    /// Built-in services in Home Screen order.
    static let builtIn: [any ServiceModule] = [
        YouTube(), Netflix(), DisneyPlus(), PrimeVideo(), HBOMax(), Spotify(), Plex(), Jellyfin(), Emby(),
        AdblockTest(), DRMTest(),
    ]

    /// The module for `s`, or a plain one for apps the user added.
    static func handlesNavigation(_ s: Service) -> Bool { module(for: s).handlesNavigation }

    static func module(for s: Service) -> any ServiceModule {
        builtIn.first { $0.service.id == s.id } ?? Custom(service: s)
    }

    /// Apps added in Settings get nothing beyond the shared scripts.
    private struct Custom: ServiceModule {
        let service: Service
    }
}
