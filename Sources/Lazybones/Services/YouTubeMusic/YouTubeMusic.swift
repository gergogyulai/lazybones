import Foundation

struct YouTubeMusic: ServiceModule {
    let service = Service(
        id: "ytmusic", name: "YouTube Music", url: URL(string: "https://music.youtube.com")!,
        tint: RGB(0.3, 0.0, 0.0), agent: .safari, navigation: .spatial,
        symbol: "music.note.house.fill", tagline: "Songs, albums, covers and remixes",
        accentTint: RGB(1.0, 0.0, 0.2), builtIn: true)
    let brand: Brand? = Brand(
        logo: "ytmusic-logo.svg", mark: "ytmusic-mark.svg",
        plate: [RGB(hex: 0x282828), RGB(hex: 0x0F0F0F)], accent: RGB(hex: 0xFF0033),
        logoWidth: 0.6)

    let pausesInBackground = false

    /// The player bar's button, so YouTube Music's own state stays right.
    let playPauseScript: String? = #"""
    (() => {
      const b = document.querySelector('ytmusic-player-bar #play-pause-button');
      if (!b) return 'no player';
      b.click();
      return b.getAttribute('aria-label') || 'toggled';
    })()
    """#
}
