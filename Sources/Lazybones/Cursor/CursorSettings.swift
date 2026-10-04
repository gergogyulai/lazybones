import Foundation

/// How the remote gets around a page. Saved per app.
enum Navigation: String, Codable, CaseIterable {
    /// The page gets the clickpad as arrow keys and Return, for sites with a TV interface of their own.
    case keys
    /// A focus ring moved between links and buttons (`Scripts.spatialNav`, or the module's own).
    case spatial
    /// A pointer that touch and the clickpad move, and that clicks what it's over (`CursorController`).
    case cursor

    var title: String {
        switch self {
        case .keys: "Arrow Keys"
        case .spatial: "Focus"
        case .cursor: "Cursor"
        }
    }

    var detail: String {
        switch self {
        case .keys: "The site gets the clickpad as arrow keys, for sites with their own TV layout"
        case .spatial: "Moves focus between a desktop site’s links and buttons"
        case .cursor: "A pointer you move with touch or the clickpad, like a mouse"
        }
    }
}

/// How the cursor behaves in one app. Saved with the app (`Service.cursor`).
struct CursorSettings: Codable, Equatable {
    /// How strongly the cursor is drawn to what can be clicked. With touch it's pulled onto a button
    /// and slows over it; with the clickpad a click hops to the next button in that direction.
    enum Snapping: String, Codable, CaseIterable {
        case off, light, medium, hard

        var title: String { rawValue.capitalized }
    }

    enum Size: String, Codable, CaseIterable {
        case small, medium, large

        var title: String { rawValue.capitalized }
    }

    /// Which way turning clockwise around the clickpad's ring scrolls.
    enum ScrollDirection: String, Codable, CaseIterable {
        case clockwiseDown, clockwiseUp

        var title: String { self == .clockwiseDown ? "Down" : "Up" }
    }

    /// Move it by sliding a finger on the touch surface.
    var followsTouch = true
    /// Move it with the clickpad's ring: a click nudges (or hops, with snapping), holding glides.
    var followsArrows = true
    /// 0...1 for each; the middle is the default and each end is a quarter or four times as fast.
    var touchSpeed = 0.5
    var arrowSpeed = 0.5
    var snapping = Snapping.medium
    var size = Size.medium
    /// Circle the outer ring to scroll what's under the cursor.
    var ringScrolls = true
    var scrollSpeed = 0.5
    var scrollDirection = ScrollDirection.clockwiseDown
    /// Scrolling carries on for a moment after the finger lifts mid-turn, as on a trackpad.
    var scrollMomentum = true

    init() {}

    // Field by field, so settings saved by an older (or newer) build still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CursorSettings()
        followsTouch = try c.decodeIfPresent(Bool.self, forKey: .followsTouch) ?? d.followsTouch
        followsArrows = try c.decodeIfPresent(Bool.self, forKey: .followsArrows) ?? d.followsArrows
        touchSpeed = try c.decodeIfPresent(Double.self, forKey: .touchSpeed) ?? d.touchSpeed
        arrowSpeed = try c.decodeIfPresent(Double.self, forKey: .arrowSpeed) ?? d.arrowSpeed
        snapping = (try? c.decodeIfPresent(Snapping.self, forKey: .snapping)) ?? d.snapping
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? d.size
        ringScrolls = try c.decodeIfPresent(Bool.self, forKey: .ringScrolls) ?? d.ringScrolls
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? d.scrollSpeed
        scrollDirection = (try? c.decodeIfPresent(ScrollDirection.self, forKey: .scrollDirection)) ?? d.scrollDirection
        scrollMomentum = try c.decodeIfPresent(Bool.self, forKey: .scrollMomentum) ?? d.scrollMomentum
    }

    /// A 0...1 speed setting as a multiplier: ¼× at 0, 1× in the middle, 4× at 1.
    static func gain(_ setting: Double) -> Double { pow(16, min(max(setting, 0), 1) - 0.5) }
}
