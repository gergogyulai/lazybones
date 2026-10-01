import Foundation

struct Netflix: ServiceModule {
    let service = Service(
        id: "netflix", name: "Netflix", url: URL(string: "https://www.netflix.com/browse")!,
        tint: RGB(0.55, 0.02, 0.05), agent: .safari, spatialNav: true,
        symbol: "film.stack.fill", tagline: "Pick up where you left off",
        accentTint: RGB(0.9, 0.05, 0.1), builtIn: true)
    let brand: Brand? = Brand(
        logo: "netflix-logo.svg", mark: "netflix-mark.svg",
        plate: [RGB(hex: 0x221F1F), RGB(hex: 0x000000)], accent: RGB(hex: 0xE50914),
        logoWidth: 0.58)

    /// The shared navigation treats Netflix as a pile of links. This one knows its rows, sliders and
    /// details panel, and moves through them the way the TV app does.
    var spatialNavScript: String? { Self.navigation }
}
