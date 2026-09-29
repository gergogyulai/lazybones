// swift-tools-version: 6.0
import PackageDescription

// Layering: the leaf modules know nothing about each other or about the app; Lull is the only
// place they meet. Keep it that way, so each can be understood (and tested) on its own.
let package = Package(
    name: "Lull",
    platforms: [.macOS("15.4")],
    products: [
        .executable(name: "Lull", targets: ["Lull"]),
    ],
    targets: [
        // The Siri Remote: buttons, touch surface, battery. Emits RemoteEvents.
        .target(name: "SiriRemote"),
        // LG webOS TV control over the LAN: pairing, volume, mute, power, discovery.
        .target(name: "LGTV"),
        // Mac audio outputs, per-device volume and network state (CoreAudio, CoreWLAN, Network).
        .target(name: "MacSystem"),
        // The launcher app.
        .executableTarget(name: "Lull", dependencies: ["SiriRemote", "LGTV", "MacSystem"]),
        .testTarget(name: "LullTests", dependencies: ["Lull", "LGTV", "MacSystem"]),
    ],
    swiftLanguageModes: [.v5]
)
