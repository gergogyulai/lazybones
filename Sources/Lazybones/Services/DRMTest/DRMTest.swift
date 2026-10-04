import Foundation

/// The EME/DRM checks themselves run on every service (`Scripts.probe`), for the debug overlay.
struct DRMTest: ServiceModule {
    let service = Service(
        id: "drm", name: "DRM test", url: URL(string: "https://bitmovin.com/demos/drm")!,
        tint: RGB(0.2, 0.2, 0.2), agent: .safari, navigation: .spatial,
        symbol: "lock.shield.fill", tagline: "Probe FairPlay and Widevine playback",
        accentTint: RGB(0.45, 0.45, 0.45), builtIn: true)
}
