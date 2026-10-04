import Foundation

struct Twitch: ServiceModule {
    let service = Service(
        id: "twitch", name: "Twitch", url: URL(string: "https://www.twitch.tv")!,
        tint: RGB(0.2, 0.1, 0.4), agent: .safari, navigation: .spatial,
        symbol: "bubble.left.and.text.bubble.right.fill", tagline: "Live streams: games, music and just chatting",
        accentTint: RGB(0.57, 0.27, 1.0), builtIn: true)
    let brand: Brand? = Brand(
        logo: "twitch-logo.svg", mark: "twitch-mark.svg",
        plate: [RGB(hex: 0xA970FF), RGB(hex: 0x772CE8)], accent: RGB(hex: 0x9146FF),
        logoWidth: 0.6)
}
