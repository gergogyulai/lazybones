import Foundation

struct PrimeVideo: ServiceModule {
    let service = Service(
        id: "prime", name: "Prime Video", url: URL(string: "https://www.primevideo.com")!,
        tint: RGB(0.0, 0.3, 0.55), agent: .safari, navigation: .spatial,
        symbol: "play.circle.fill", tagline: "Originals, movies and live sport",
        accentTint: RGB(0.0, 0.62, 0.95), builtIn: true)
    let brand: Brand? = Brand(
        logo: "prime-logo.png",
        plate: [RGB(hex: 0x0D2A45), RGB(hex: 0x00050D)], accent: RGB(hex: 0x1C89E3),
        logoWidth: 0.62, shelfHeight: 1.3)
}
