import AppKit
import SwiftUI

/// A built-in service's official artwork: its logo and symbol as the service publishes them, on a
/// plate in its own colors. The files are in Resources/Brands (where each came from is in
/// SOURCES.md there), shipped as they were downloaded, and drawn at whatever size the icon needs.
struct Brand: Sendable {
    /// The full logo, for the icon and the top shelf.
    var logo: String
    /// The symbol on its own, for icons too small for the full logo. Without one, the logo is used.
    var mark: String?
    /// The icon's background, top-leading to bottom-trailing. The last color stands for the service
    /// where a single one is needed (`Service.color`), so it's usually the darkest.
    var plate: [RGB]
    /// The brand's signature color, for the top shelf's glow, the keyboard's action key and the like.
    var accent: RGB
    /// The logo's width on the icon, as a fraction of the icon's, since each file has its own
    /// proportions and clear space.
    var logoWidth: CGFloat = 0.6
    /// The logo's height in the top shelf, as a multiple of the shelf's title size.
    var shelfHeight: CGFloat = 1

    @MainActor var logoImage: NSImage? { Self.image(logo) }
    @MainActor var markImage: NSImage? { mark.flatMap(Self.image) ?? logoImage }

    var colors: [Color] { plate.map(\.color) }

    /// Where the files are: the app's Resources/Brands. A missing file gives nil, and the icon falls
    /// back to its symbol, as in a `swift run` build that has no app bundle around it.
    @MainActor static var directory = Bundle.main.resourceURL?.appendingPathComponent("Brands", isDirectory: true)
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = directory?.appendingPathComponent(name), let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

extension RGB {
    /// From a hex triplet like 0xE50914, the way brand guidelines give their colors.
    init(hex: UInt32) {
        self.init(Double(hex >> 16 & 0xFF) / 255, Double(hex >> 8 & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
