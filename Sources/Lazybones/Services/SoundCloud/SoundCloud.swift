import Foundation

struct SoundCloud: ServiceModule {
    let service = Service(
        id: "soundcloud", name: "SoundCloud", url: URL(string: "https://soundcloud.com/discover")!,
        tint: RGB(0.35, 0.12, 0.0), agent: .safari, navigation: .spatial,
        symbol: "cloud.fill", tagline: "New artists, mixes and DJ sets",
        accentTint: RGB(1.0, 0.33, 0.0), builtIn: true)
    let brand: Brand? = Brand(
        logo: "soundcloud-logo.svg",
        plate: [RGB(hex: 0xFF7A1A), RGB(hex: 0xFF5500)], accent: RGB(hex: 0xFF5500),
        logoWidth: 0.74)

    let pausesInBackground = false

    /// uBlock Origin Lite's SoundCloud filters redirect media requests for `sndcdn.com/audio/` to a
    /// silent clip, to drop audio ads. WebKit loads the tracks themselves that way too, so nothing
    /// plays, the same as Spotify (see `Spotify.allowsAdBlocking`).
    let allowsAdBlocking = false

    /// The player bar's button, so SoundCloud's own state stays right. It's disabled until a track
    /// has been picked.
    let playPauseScript: String? = #"""
    (() => {
      const b = document.querySelector('.playControls__play');
      if (!b || b.classList.contains('disabled')) return 'no player';
      const was = b.classList.contains('playing');
      b.click();
      return was ? 'pause' : 'play';
    })()
    """#
}
