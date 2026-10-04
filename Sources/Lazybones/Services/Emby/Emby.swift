import Foundation

/// Self-hosted: defaults to port 8096 on this Mac; set the real address in Settings.
struct Emby: ServiceModule {
    let service = Service(
        id: "emby", name: "Emby", url: URL(string: "http://localhost:8096/web/index.html")!,
        tint: RGB(0.18, 0.45, 0.17), agent: .safari, navigation: .spatial,
        symbol: "server.rack", tagline: "Personal media server",
        accentTint: RGB(0.32, 0.71, 0.29), builtIn: true)
    let brand: Brand? = Brand(
        logo: "emby-logo.png", mark: "emby-mark.png",
        plate: [RGB(hex: 0x2B2B2B), RGB(hex: 0x1C1C1C)], accent: RGB(hex: 0x52B54B),
        logoWidth: 0.66, shelfHeight: 1.3)
}
