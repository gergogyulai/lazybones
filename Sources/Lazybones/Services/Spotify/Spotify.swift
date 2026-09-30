import Foundation
import WebKit

/// Spotify's web player. Safari gets FairPlay playback there, so it needs no special identity.
/// It's a music service, so it keeps playing behind the Home Screen and Play/Pause still reaches it.
struct Spotify: ServiceModule {
    let service = Service(
        id: "spotify", name: "Spotify", url: URL(string: "https://open.spotify.com/")!,
        tint: RGB(0.05, 0.4, 0.2), agent: .safari, spatialNav: true,
        symbol: "music.note", tagline: "Music and podcasts, playing while you browse",
        accentTint: RGB(0.12, 0.84, 0.38), builtIn: true)

    let pausesInBackground = false

    /// The player bar's own button is what keeps Spotify's state (and the media session) right; poking
    /// the media element behind its back leaves the UI out of step.
    let playPauseScript: String? = #"""
    (() => {
      const b = document.querySelector('[data-testid="control-button-playpause"]');
      if (!b) return 'no player';
      b.click();
      return b.getAttribute('aria-label') || 'toggled';
    })()
    """#

    /// The desktop layout is dense for a room across from the screen.
    static let pageZoom: CGFloat = 1.25

    /// No use for an "Install app" nudge on a TV.
    let styles = [#"a[href*="spotify.com/download"] { display: none !important; }"#]

    @MainActor func prepare(_ webView: WKWebView, for s: Service) {
        webView.pageZoom = Self.pageZoom
    }
}
