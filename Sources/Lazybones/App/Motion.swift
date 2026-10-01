import AppKit
import SwiftUI

/// Every animation in the app, by what it's for, so the whole app moves as one system: focus is
/// quick with a little life in it, things arriving settle without overshoot, things leaving get
/// out of the way faster than they came.
///
/// With Reduce Motion on (System Settings ▸ Accessibility ▸ Display), movement gives way to
/// fades: nothing zooms, tilts or bounces, but changes still ease rather than cut.
enum Motion {
    /// Focus moving from one item to the next, and the item lifting to meet it.
    static var focus: Animation { reduced ? .easeInOut(duration: 0.15) : .spring(duration: 0.25, bounce: 0.2) }
    /// A screen or panel arriving: Settings, the app switcher, Control Center, the keyboard.
    static var present: Animation { reduced ? .easeOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.1) }
    /// The same leaving.
    static var dismiss: Animation { reduced ? .easeIn(duration: 0.2) : .spring(duration: 0.3, bounce: 0) }
    /// Something opening in place, like a list unfolding.
    static var expand: Animation { reduced ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.1) }
    /// Content swapping in the same place: the top shelf, a settings page, a launch screen.
    static var crossfade: Animation { .easeInOut(duration: reduced ? 0.25 : 0.4) }
    /// A grid or list moving to bring focus into view.
    static var scroll: Animation { reduced ? .easeInOut(duration: 0.25) : .spring(duration: 0.5, bounce: 0.08) }
    /// A value changing: a slider filling, a level rising.
    static var value: Animation { .spring(duration: 0.25) }
    /// An app growing out of its icon, and shrinking back into it.
    static var zoomIn: Animation { reduced ? .easeOut(duration: 0.3) : .spring(duration: 0.55, bounce: 0) }
    static var zoomOut: Animation { reduced ? .easeOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0) }

    /// The user asked for less motion.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

extension View {
    /// Presses the view in and lets it spring back each time `trigger` changes while `active`: how
    /// a click on the remote shows on the focused item.
    func pressEffect(trigger: Int, active: Bool) -> some View {
        keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, scale in
            content.scaleEffect(active ? scale : 1)
        } keyframes: { _ in
            CubicKeyframe(0.94, duration: 0.07)
            SpringKeyframe(1, duration: 0.3, spring: .init(duration: 0.3, bounce: 0.45))
        }
    }
}
