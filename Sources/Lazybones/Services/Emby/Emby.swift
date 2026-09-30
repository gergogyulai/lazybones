import Foundation

/// Self-hosted: defaults to port 8096 on this Mac; set the real address in Settings.
struct Emby: ServiceModule {
    let service = Service(
        id: "emby", name: "Emby", url: URL(string: "http://localhost:8096/web/index.html")!,
        tint: RGB(0.18, 0.45, 0.17), agent: .safari, spatialNav: true,
        symbol: "server.rack", tagline: "Personal media server",
        accentTint: RGB(0.32, 0.71, 0.29), builtIn: true)
}
