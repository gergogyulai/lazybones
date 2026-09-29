import AppKit
import WebKit

/// How a web view introduces itself to sites.
enum BrowserIdentity {
    /// The installed Safari's version, so the user agent reads as a current Safari.
    private static let safariVersion: String =
        NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
        ?? "26.0"

    // youtube.com/tv only serves the TV ("leanback") UI to TV-like user agents.
    private static let tvUserAgent =
        "Mozilla/5.0 (Linux armv7l) Cobalt/23.lts.4.0-gold (unlike Gecko) v8/8.8.278.8-jit gles Starboard/15, Sony_STV_2023_PS5/ (Sony, BRAVIA, Wired)"

    /// Call before the web view is created.
    @MainActor static func configure(_ config: WKWebViewConfiguration, as agent: Service.Agent) {
        if agent == .safari {
            // Appends to WebKit's real UA so it reads as the installed Safari.
            config.applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"
        }
    }

    @MainActor static func apply(to webView: WKWebView, as agent: Service.Agent) {
        if agent == .tv { webView.customUserAgent = tvUserAgent }
    }
}
