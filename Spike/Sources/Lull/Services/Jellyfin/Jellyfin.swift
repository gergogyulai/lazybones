import Foundation

/// Self-hosted: defaults to port 8096 on this Mac; set the real address in Settings.
struct Jellyfin: ServiceModule {
    let service = Service(
        id: "jellyfin", name: "Jellyfin", url: URL(string: "http://localhost:8096/web/")!,
        tint: RGB(0.0, 0.45, 0.7), agent: .tv, spatialNav: false,
        symbol: "play.square.stack.fill", tagline: "Your own media, on your own server",
        accentTint: RGB(0.67, 0.36, 0.76), builtIn: true)

    /// Jellyfin's web client has its own arrow-key focus handling (its TV layout).
    let handlesNavigation = true
}
