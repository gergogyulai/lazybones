import Foundation

struct DisneyPlus: ServiceModule {
    let service = Service(
        id: "disney", name: "Disney+", url: URL(string: "https://www.disneyplus.com/home")!,
        tint: RGB(0.05, 0.15, 0.45), agent: .safari, spatialNav: true,
        symbol: "sparkles", tagline: "Disney, Pixar, Marvel, Star Wars and National Geographic",
        accentTint: RGB(0.1, 0.45, 0.85), builtIn: true)
    let brand: Brand? = Brand(
        logo: "disney-logo.png",
        plate: [RGB(hex: 0x002638), RGB(hex: 0x00525F)], accent: RGB(hex: 0x00959F),
        logoWidth: 0.7, shelfHeight: 1.9)
}
