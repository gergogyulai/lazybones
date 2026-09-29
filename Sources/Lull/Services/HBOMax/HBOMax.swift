import Foundation

struct HBOMax: ServiceModule {
    let service = Service(
        id: "max", name: "HBO Max", url: URL(string: "https://play.hbomax.com")!,
        tint: RGB(0.12, 0.05, 0.4), agent: .safari, spatialNav: true,
        symbol: "tv.fill", tagline: "Prestige series, blockbuster films",
        accentTint: RGB(0.45, 0.2, 0.95), builtIn: true)
}
