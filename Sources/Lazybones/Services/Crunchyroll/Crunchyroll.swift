import Foundation

struct Crunchyroll: ServiceModule {
    let service = Service(
        id: "crunchyroll", name: "Crunchyroll", url: URL(string: "https://www.crunchyroll.com")!,
        tint: RGB(0.1, 0.1, 0.1), agent: .safari, navigation: .spatial,
        symbol: "play.square.stack.fill", tagline: "Anime, subbed and dubbed, as it airs in Japan",
        accentTint: RGB(0.96, 0.46, 0.1), builtIn: true)
    let brand: Brand? = Brand(
        logo: "crunchyroll-logo.svg",
        plate: [RGB(hex: 0x2A2A2A), RGB(hex: 0x000000)], accent: RGB(hex: 0xFF5E00),
        logoWidth: 0.72)
}
