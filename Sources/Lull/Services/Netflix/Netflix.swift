import Foundation

struct Netflix: ServiceModule {
    let service = Service(
        id: "netflix", name: "Netflix", url: URL(string: "https://www.netflix.com/browse")!,
        tint: RGB(0.55, 0.02, 0.05), agent: .safari, spatialNav: true,
        symbol: "film.stack.fill", tagline: "Pick up where you left off",
        accentTint: RGB(0.9, 0.05, 0.1), builtIn: true)
}
