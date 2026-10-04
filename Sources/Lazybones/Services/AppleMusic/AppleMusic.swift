import Foundation

struct AppleMusic: ServiceModule {
    let service = Service(
        id: "applemusic", name: "Apple Music", url: URL(string: "https://music.apple.com")!,
        tint: RGB(0.4, 0.05, 0.1), agent: .safari, navigation: .spatial,
        symbol: "music.note", tagline: "Songs, albums, radio and lyrics",
        accentTint: RGB(0.98, 0.18, 0.3), builtIn: true)
    let brand: Brand? = Brand(
        logo: "applemusic-logo.svg",
        plate: [RGB(hex: 0xFA586A), RGB(hex: 0xFA233B)], accent: RGB(hex: 0xFA233B),
        logoWidth: 0.62)

    let pausesInBackground = false

    /// Through MusicKit, which the web player is built on, so its controls follow along.
    let playPauseScript: String? = #"""
    (() => {
      const m = window.MusicKit && MusicKit.getInstance();
      if (!m || !m.nowPlayingItem) return 'no player';
      if (m.isPlaying) { m.pause(); return 'pause'; }
      m.play(); return 'play';
    })()
    """#
}
