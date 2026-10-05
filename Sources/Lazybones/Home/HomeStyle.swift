import SwiftUI

/// How the Home Screen moves as focus goes around it.
enum HomeMotion: String, Codable, CaseIterable {
    /// Icons lean into each move and spring back, as on tvOS.
    case lively
    /// The same, gentler and without overshoot.
    case smooth
    /// Focus just glides; nothing leans or tilts.
    case subtle

    var title: String {
        switch self {
        case .lively: "Lively"
        case .smooth: "Smooth"
        case .subtle: "Subtle"
        }
    }

    var detail: String {
        switch self {
        case .lively: "Icons lean into each move and spring back"
        case .smooth: "Gentle and fluid, with no bounce"
        case .subtle: "Focus glides without leaning or tilting"
        }
    }

    /// Focus moving from one icon to the next, and the icon lifting to meet it.
    var focus: Animation {
        if Motion.reduced { return Motion.focus }
        return switch self {
        case .lively: .spring(duration: 0.3, bounce: 0.24)
        case .smooth: .spring(duration: 0.38, bounce: 0.04)
        case .subtle: .easeOut(duration: 0.22)
        }
    }

    /// The grid moving to bring a row into view, and the shelf receding behind it.
    var scroll: Animation {
        if Motion.reduced { return Motion.scroll }
        return switch self {
        case .lively: .spring(duration: 0.55, bounce: 0.1)
        case .smooth: .spring(duration: 0.6, bounce: 0)
        case .subtle: .easeInOut(duration: 0.35)
        }
    }

    /// How far, in degrees, the focused icon leans toward each move.
    var lean: Double {
        switch self {
        case .lively: 9
        case .smooth: 5
        case .subtle: 0
        }
    }

    /// The icon swinging into a lean. A spring, so a lean the other way picks up from wherever the
    /// last one had got to, at its speed, instead of starting over.
    var push: Animation { .spring(duration: 0.16, bounce: 0) }

    /// The icon settling after leaning.
    var settle: Animation {
        self == .lively ? .spring(duration: 0.6, bounce: 0.38) : .spring(duration: 0.55, bounce: 0)
    }

    /// The light on the icons swinging round to the edge focus came from.
    var glint: Animation { .spring(duration: 0.5, bounce: 0) }

    /// Whether a band of light sweeps across an icon as it takes focus.
    var sweeps: Bool { self != .subtle }

    /// Whether the focused icon tilts under a thumb resting on the clickpad.
    var tilts: Bool { self != .subtle }
}

/// How much the focused icon grows.
enum FocusSize: String, Codable, CaseIterable {
    case small, medium, large

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 1.08
        case .medium: 1.15
        case .large: 1.22
        }
    }
}

/// When app names show under their icons.
enum IconLabels: String, Codable, CaseIterable {
    case focused, always, never

    var title: String {
        switch self {
        case .focused: "When Focused"
        case .always: "Always"
        case .never: "Never"
        }
    }
}
