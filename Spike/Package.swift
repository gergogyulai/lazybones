// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lull",
    platforms: [.macOS("15.4")],
    products: [
        .library(name: "SiriRemote", targets: ["SiriRemote"]),
        .executable(name: "Lull", targets: ["Lull"]),
    ],
    targets: [
        // Everything that talks to the Siri Remote: buttons, touch surface, battery.
        .target(name: "SiriRemote"),
        // The launcher app. Sees only SiriRemote's public API.
        .executableTarget(name: "Lull", dependencies: ["SiriRemote"]),
    ],
    swiftLanguageModes: [.v5]
)
