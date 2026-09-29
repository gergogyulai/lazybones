import Foundation

struct PrimeVideo: ServiceModule {
    let service = Service(
        id: "prime", name: "Prime Video", url: URL(string: "https://www.primevideo.com")!,
        tint: RGB(0.0, 0.3, 0.55), agent: .safari, spatialNav: true,
        symbol: "play.circle.fill", tagline: "Originals, movies and live sport",
        accentTint: RGB(0.0, 0.62, 0.95), builtIn: true)
}
