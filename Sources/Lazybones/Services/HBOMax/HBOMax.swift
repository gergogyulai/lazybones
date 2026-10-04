import Foundation

struct HBOMax: ServiceModule {
    let service = Service(
        id: "max", name: "HBO Max", url: URL(string: "https://play.hbomax.com")!,
        tint: RGB(0.12, 0.05, 0.4), agent: .safari, navigation: .spatial,
        symbol: "tv.fill", tagline: "Prestige series, blockbuster films",
        accentTint: RGB(0.45, 0.2, 0.95), builtIn: true)
    let brand: Brand? = Brand(
        logo: "max-logo.svg",
        plate: [RGB(hex: 0x0A1A9C), RGB(hex: 0x04006C)], accent: RGB(hex: 0x2D5BFF),
        logoWidth: 0.4, shelfHeight: 1.6)
}
