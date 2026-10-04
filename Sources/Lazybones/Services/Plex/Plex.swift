import Foundation

struct Plex: ServiceModule {
    let service = Service(
        id: "plex", name: "Plex", url: URL(string: "https://app.plex.tv/desktop")!,
        tint: RGB(0.12, 0.12, 0.13), agent: .safari, navigation: .spatial,
        symbol: "chevron.forward.circle.fill", tagline: "Your media server, and free movies and TV",
        accentTint: RGB(0.9, 0.63, 0.05), builtIn: true)
    let brand: Brand? = Brand(
        logo: "plex-logo.svg",
        plate: [RGB(hex: 0x2A2A2A), RGB(hex: 0x1F1F1F)], accent: RGB(hex: 0xEBAF00),
        logoWidth: 0.5)
}
