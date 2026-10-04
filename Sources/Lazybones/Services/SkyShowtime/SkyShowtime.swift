import Foundation

struct SkyShowtime: ServiceModule {
    let service = Service(
        id: "skyshowtime", name: "SkyShowtime", url: URL(string: "https://www.skyshowtime.com/watch/home")!,
        tint: RGB(0.05, 0.05, 0.2), agent: .safari, navigation: .spatial,
        symbol: "sparkles.tv.fill", tagline: "Paramount, Peacock and Universal, in one place",
        accentTint: RGB(0.4, 0.3, 0.95), builtIn: true)
    let brand: Brand? = Brand(
        logo: "skyshowtime-logo.svg",
        plate: [RGB(hex: 0x3A2C8C), RGB(hex: 0x0E0A2A)], accent: RGB(hex: 0x795FE3),
        logoWidth: 0.72)
}
