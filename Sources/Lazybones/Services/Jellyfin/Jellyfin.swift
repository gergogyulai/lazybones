import Foundation

/// Self-hosted: defaults to port 8096 on this Mac; set the real address in Settings.
struct Jellyfin: ServiceModule {
    let service = Service(
        id: "jellyfin", name: "Jellyfin", url: URL(string: "http://localhost:8096/web/")!,
        tint: RGB(0.0, 0.45, 0.7), agent: .tv, navigation: .keys,
        symbol: "play.square.stack.fill", tagline: "Your own media, on your own server",
        accentTint: RGB(0.67, 0.36, 0.76), builtIn: true)
    let brand: Brand? = Brand(
        logo: "jellyfin-logo.svg", mark: "jellyfin-mark.svg",
        plate: [RGB(hex: 0x202020), RGB(hex: 0x101010)], accent: RGB(hex: 0xAA5CC3),
        logoWidth: 0.74, shelfHeight: 1.4)

    /// Jellyfin's web client has its own arrow-key focus handling (its TV layout).
    let handlesNavigation = true
}
