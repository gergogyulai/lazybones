import Foundation

/// Magyar Telekom's TV GO: Hungarian live channels, catch-up and on demand.
struct TelekomTVGO: ServiceModule {
    let service = Service(
        id: "tvgo", name: "TV GO", url: URL(string: "https://player.telekomtvgo.hu")!,
        tint: RGB(0.3, 0.0, 0.2), agent: .safari, navigation: .spatial,
        symbol: "antenna.radiowaves.left.and.right", tagline: "Hungarian live TV, catch-up and on demand",
        accentTint: RGB(0.89, 0.0, 0.45), builtIn: true)
    /// Its logo is the TV GO app icon, a square that fills its own background, so the plate continues
    /// its gradient. The Telekom "T" stands in as the mark, where a silhouette is wanted.
    let brand: Brand? = Brand(
        logo: "tvgo-logo.png", mark: "tvgo-mark.svg",
        plate: [RGB(hex: 0xFF51AB), RGB(hex: 0xEB2A87)], accent: RGB(hex: 0xE20074),
        logoWidth: 0.5, shelfHeight: 1.6)
}
