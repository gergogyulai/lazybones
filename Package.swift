// swift-tools-version: 6.0
import PackageDescription

// Layering: the leaf modules know nothing about each other or about the app; Lazybones is the only
// place they meet. Keep it that way, so each can be understood (and tested) on its own.
let package = Package(
    name: "Lazybones",
    platforms: [.macOS("15.4")],
    products: [
        .executable(name: "Lazybones", targets: ["Lazybones"]),
    ],
    targets: [
        // The Siri Remote: buttons, touch surface, battery. Emits RemoteEvents.
        .target(name: "SiriRemote"),
        // LG webOS TV control over the LAN: pairing, volume, mute, power, discovery.
        .target(name: "LGTV"),
        // Mac audio outputs, per-device volume and network state (CoreAudio, CoreWLAN, Network).
        .target(name: "MacSystem"),
        // The iPhone's Apple TV Remote, answered as an Apple TV (atv-core, built from Native/AppleTVBridge).
        .target(name: "PhoneRemote"),
        // The launcher app.
        .executableTarget(name: "Lazybones", dependencies: ["SiriRemote", "LGTV", "MacSystem", "PhoneRemote"]),
        .testTarget(name: "LazybonesTests", dependencies: ["Lazybones", "LGTV", "MacSystem", "PhoneRemote"]),
    ],
    swiftLanguageModes: [.v5]
)
