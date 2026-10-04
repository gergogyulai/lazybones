import Foundation

struct AppleTV: ServiceModule {
    let service = Service(
        id: "appletv", name: "Apple TV", url: URL(string: "https://tv.apple.com")!,
        tint: RGB(0.1, 0.1, 0.12), agent: .safari, navigation: .spatial,
        symbol: "appletv.fill", tagline: "Apple Originals, films and Friday Night Baseball",
        accentTint: RGB(0.6, 0.6, 0.65), builtIn: true)
    let brand: Brand? = Brand(
        logo: "appletv-logo.svg",
        plate: [RGB(hex: 0x333336), RGB(hex: 0x000000)], accent: RGB(hex: 0x0A84FF),
        logoWidth: 0.42, shelfHeight: 1.3)
}
