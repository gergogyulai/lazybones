import Foundation

struct ParamountPlus: ServiceModule {
    let service = Service(
        id: "paramount", name: "Paramount+", url: URL(string: "https://www.paramountplus.com")!,
        tint: RGB(0.0, 0.1, 0.4), agent: .safari, navigation: .spatial,
        symbol: "mountain.2.fill", tagline: "Paramount films, CBS, Nickelodeon and live sport",
        accentTint: RGB(0.0, 0.4, 1.0), builtIn: true)
    let brand: Brand? = Brand(
        logo: "paramount-logo.png",
        plate: [RGB(hex: 0x1E3FA8), RGB(hex: 0x0A1D61)], accent: RGB(hex: 0x0064FF),
        logoWidth: 0.5, shelfHeight: 1.9)
}
