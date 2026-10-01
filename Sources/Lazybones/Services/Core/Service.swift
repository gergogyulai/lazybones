import AppKit
import SwiftUI

struct Service: Identifiable, Codable, Equatable {
    enum Agent: String, Codable, CaseIterable { case safari, tv }

    var id: String
    var name: String
    var url: URL
    var tint: RGB
    var agent: Agent
    var spatialNav: Bool
    /// Launcher presentation: SF Symbol for the icon, a line for the top shelf, and the icon's highlight.
    var symbol = "play.tv.fill"
    var tagline = ""
    var accentTint: RGB? = nil
    /// Load uBlock Origin Lite into the app's web view, along with the module's own ad blocking.
    var blocksAds = true
    /// Load SponsorBlock, on the sites it works on (YouTube), to skip sponsor segments and the like.
    var skipsSponsors = true
    /// Built-ins can be hidden but not deleted, so new defaults can be merged into saved settings.
    var builtIn = false

    /// Official artwork, for built-ins that have it. It takes the place of the symbol and the saved
    /// colors, so a built-in looks right however old the settings it was saved in.
    var brand: Brand? { builtIn ? ServiceModules.module(for: self).brand : nil }

    var color: Color { brand?.plate.last?.color ?? tint.color }
    var accent: Color? { brand?.accent.color ?? accentTint?.color }
    var gradient: [Color] { brand?.colors ?? [accent ?? color, color] }

    static func custom() -> Service {
        Service(id: UUID().uuidString, name: "New App", url: URL(string: "https://example.com")!,
                tint: RGB(0.25, 0.3, 0.4), agent: .safari, spatialNav: true, symbol: "globe",
                accentTint: RGB(0.4, 0.5, 0.65))
    }

    /// A web address as typed: "example.com" means https://example.com.
    static func url(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme), url.host()?.isEmpty == false else { return nil }
        return url
    }

    /// Built-ins in Home Screen order, one per module in `ServiceModules.builtIn`.
    static let defaults: [Service] = ServiceModules.builtIn.map(\.service)
}

extension Service {
    // Field by field, so apps saved by an older build still load. In an extension, to keep the
    // memberwise initializer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(URL.self, forKey: .url)
        tint = try c.decode(RGB.self, forKey: .tint)
        agent = try c.decode(Agent.self, forKey: .agent)
        spatialNav = try c.decode(Bool.self, forKey: .spatialNav)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? symbol
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline) ?? tagline
        accentTint = try c.decodeIfPresent(RGB.self, forKey: .accentTint)
        blocksAds = try c.decodeIfPresent(Bool.self, forKey: .blocksAds) ?? blocksAds
        skipsSponsors = try c.decodeIfPresent(Bool.self, forKey: .skipsSponsors) ?? skipsSponsors
        builtIn = try c.decodeIfPresent(Bool.self, forKey: .builtIn) ?? builtIn
    }
}

/// A Codable sRGB color, since SwiftUI's Color isn't.
struct RGB: Codable, Equatable {
    var r, g, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { (self.r, self.g, self.b) = (r, g, b) }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(c.redComponent, c.greenComponent, c.blueComponent)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}
