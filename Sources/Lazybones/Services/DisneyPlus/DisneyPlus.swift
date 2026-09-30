import Foundation

struct DisneyPlus: ServiceModule {
    let service = Service(
        id: "disney", name: "Disney+", url: URL(string: "https://www.disneyplus.com/home")!,
        tint: RGB(0.05, 0.15, 0.45), agent: .safari, spatialNav: true,
        symbol: "sparkles", tagline: "Disney, Pixar, Marvel, Star Wars and National Geographic",
        accentTint: RGB(0.1, 0.45, 0.85), builtIn: true)
}
