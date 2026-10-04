import CoreGraphics
import Foundation
import simd
import SiriRemote

/// Where the cursor is and how input moves it, without any timers or views, so it can be tested.
/// Points are the page's on-screen coordinates, from its top left corner.
///
/// The cursor has two positions. `raw` is where input has put it. `snap` is where it shows and
/// clicks: drawn toward the centre of a nearby button, by as much as the snapping setting says.
/// Moving out of the button's reach lets it go again.
struct CursorMotion {
    var settings = CursorSettings()
    var bounds = CGSize(width: 1920, height: 1080) {
        didSet { raw = clamp(raw) }
    }
    /// What can be clicked, from `Scripts.cursorTargets`.
    var targets: [CGRect] = []
    private(set) var raw = CGPoint(x: 960, y: 540)
    /// Finger speed in surface units a second, smoothed.
    private var touchSpeed: Float = 0

    /// Lengths are given for a 1920-point-wide page, and scaled to the real one.
    var unit: CGFloat { max(bounds.width / 1920, 0.4) }

    mutating func place(at p: CGPoint) { raw = clamp(p) }

    // MARK: Snapping

    struct Snap: Equatable {
        /// Where the cursor shows and clicks.
        var point: CGPoint
        /// What it's over or held to, if anything.
        var target: CGRect?
    }

    var snap: Snap {
        guard let target = target(at: raw) else { return Snap(point: raw, target: nil) }
        let c = CGPoint(x: target.midX, y: target.midY)
        let pull = pull(for: target)
        return Snap(point: CGPoint(x: raw.x + (c.x - raw.x) * pull, y: raw.y + (c.y - raw.y) * pull), target: target)
    }

    /// How far outside a target its pull reaches.
    private var reach: CGFloat {
        switch settings.snapping {
        case .off, .light: 0
        case .medium: 14 * unit
        case .hard: 32 * unit
        }
    }

    /// How far toward a target's centre the cursor is drawn: fully for a button, not at all for
    /// something as big as a card, which you'd want to point within.
    private func pull(for r: CGRect) -> CGFloat {
        let strength: CGFloat = switch settings.snapping {
        case .off: 0
        case .light: 0.35
        case .medium: 0.75
        case .hard: 1
        }
        let size = max(r.width, r.height)
        return strength * min(max((360 * unit - size) / (240 * unit), 0), 1)
    }

    /// Whether a target is small enough to snap to and outline; a whole-page link is neither.
    func isSnappable(_ r: CGRect) -> Bool {
        r.width <= bounds.width * 0.6 && r.height <= bounds.height * 0.5
    }

    /// The target under `p`, or within reach of it: the smallest, so a button on a card wins over the card.
    func target(at p: CGPoint) -> CGRect? {
        let reach = reach
        return targets
            .filter { isSnappable($0) && $0.insetBy(dx: -reach, dy: -reach).contains(p) }
            .min { a, b in
                let inA = a.contains(p), inB = b.contains(p)
                if inA != inB { return inA }
                return a.width * a.height < b.width * b.height
            }
    }

    /// How much a target slows the cursor passing over it, so it's easy to stop on.
    private var friction: CGFloat {
        switch settings.snapping {
        case .off: 0
        case .light: 0.15
        case .medium: 0.3
        case .hard: 0.45
        }
    }

    // MARK: Touch

    /// Moves by a finger's travel on the touch surface (y up) over `dt` seconds. Returns how far it
    /// pushed past the top or bottom edge (positive past the bottom), for scrolling the page.
    mutating func touchMove(_ delta: SIMD2<Float>, dt: TimeInterval) -> CGFloat {
        let speed = simd_length(delta) / Float(max(dt, 1 / 240))
        touchSpeed += (speed - touchSpeed) * 0.4
        // Slow fingers are precise, fast ones go far: a slow crossing of the surface covers half the
        // page, a quick one more than all of it.
        let accel = CGFloat(0.55 + min(touchSpeed, 4) * 0.45)
        let gain = CGFloat(CursorSettings.gain(settings.touchSpeed))
        var d = CGPoint(x: CGFloat(delta.x), y: CGFloat(-delta.y))
        d.x *= bounds.width * 0.8 * gain * accel
        d.y *= bounds.width * 0.8 * gain * accel
        // Friction only for a finger slowing down to stop; a quick one flies over.
        let slowing = CGFloat(min(max(1 - (touchSpeed - 0.4) / 1.4, 0), 1))
        return move(by: d, friction: friction * slowing)
    }

    // MARK: Clickpad

    /// A click on the ring: hops to the next button that way when snapping is medium or hard and
    /// there is one, else steps. At the top or bottom edge it returns a scroll instead.
    mutating func nudge(_ direction: RemoteCommand) -> CGFloat {
        let v = Self.vector(direction)
        let atEdge = (v.y > 0 && raw.y >= bounds.height - 1) || (v.y < 0 && raw.y <= 1)
        if atEdge { return v.y * bounds.height * 0.4 }
        if settings.snapping == .medium || settings.snapping == .hard, let next = hop(direction) {
            raw = clamp(CGPoint(x: next.midX, y: next.midY))
            return 0
        }
        let step = 90 * unit * CGFloat(CursorSettings.gain(settings.arrowSpeed).squareRoot())
        return move(by: CGPoint(x: v.x * step, y: v.y * step), friction: 0)
    }

    /// A held direction, `held` seconds after it was pressed: glides, gathering speed, and slows a
    /// little over buttons. Returns the push past the top or bottom edge, as `touchMove` does.
    mutating func glide(_ direction: RemoteCommand, held: TimeInterval, dt: TimeInterval) -> CGFloat {
        let v = Self.vector(direction)
        let ramp = 0.6 + min(held, 1.2) / 1.2 * 1.6
        let speed = 620 * unit * CGFloat(CursorSettings.gain(settings.arrowSpeed) * ramp * dt)
        return move(by: CGPoint(x: v.x * speed, y: v.y * speed), friction: friction * 0.6)
    }

    /// The best target in `direction`, scored as spatial navigation does: nearest along the way,
    /// strongly preferring ones in line. Medium snapping only looks half a screen ahead.
    func hop(_ direction: RemoteCommand) -> CGRect? {
        let here = snap
        let a = here.target ?? CGRect(origin: here.point, size: .zero)
        let ca = CGPoint(x: a.midX, y: a.midY)
        let horizontal = direction == .left || direction == .right
        let limit = settings.snapping == .hard ? .infinity : (horizontal ? bounds.width : bounds.height) * 0.5
        var best: CGRect?
        var bestScore = CGFloat.infinity
        for b in targets where isSnappable(b) && b != here.target {
            let cb = CGPoint(x: b.midX, y: b.midY)
            let main: CGFloat, overlap: CGFloat, cross: CGFloat
            switch direction {
            case .right:
                guard cb.x > ca.x + 4 else { continue }
                main = b.minX - a.maxX
            case .left:
                guard cb.x < ca.x - 4 else { continue }
                main = a.minX - b.maxX
            case .down:
                guard cb.y > ca.y + 4 else { continue }
                main = b.minY - a.maxY
            default:
                guard cb.y < ca.y - 4 else { continue }
                main = a.minY - b.maxY
            }
            if horizontal {
                overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
                cross = abs(cb.y - ca.y)
            } else {
                overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                cross = abs(cb.x - ca.x)
            }
            guard max(main, 0) <= limit else { continue }
            let score = max(main, 0) + (overlap > 0 ? 0 : cross * 3) + cross * 0.1
            if score < bestScore {
                bestScore = score
                best = b
            }
        }
        return best
    }

    // MARK: Moving

    private mutating func move(by d: CGPoint, friction: CGFloat) -> CGFloat {
        var d = d
        if friction > 0, let t = target(at: raw), isSnappable(t), t.contains(snap.point) {
            d.x *= 1 - friction
            d.y *= 1 - friction
        }
        let wanted = CGPoint(x: raw.x + d.x, y: raw.y + d.y)
        raw = clamp(wanted)
        return wanted.y - raw.y
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), max(bounds.width - 1, 0)), y: min(max(p.y, 0), max(bounds.height - 1, 0)))
    }

    private static func vector(_ direction: RemoteCommand) -> CGPoint {
        switch direction {
        case .left: CGPoint(x: -1, y: 0)
        case .right: CGPoint(x: 1, y: 0)
        case .up: CGPoint(x: 0, y: -1)
        default: CGPoint(x: 0, y: 1)
        }
    }
}

/// Scrolling from turns around the ring: eased out over a few frames rather than in jumps, and
/// carrying on after a flick when momentum is on.
struct RingScroll {
    /// Pixels still to scroll (positive goes down the page), and the momentum's speed in pixels a second.
    private(set) var pending: Double = 0
    private(set) var velocity: Double = 0
    private var remainder: Double = 0

    var isIdle: Bool { pending == 0 && velocity == 0 }

    /// Pixels a turn of `radians` (clockwise positive) scrolls a page `height` tall.
    static func pixels(_ radians: Float, height: CGFloat, settings: CursorSettings) -> Double {
        // A whole turn scrolls a bit over a page.
        let direction: Double = settings.scrollDirection == .clockwiseDown ? 1 : -1
        return Double(radians) / (2 * .pi) * 1.2 * Double(height) * CursorSettings.gain(settings.scrollSpeed) * direction
    }

    mutating func add(_ pixels: Double) {
        velocity = 0
        pending += pixels
    }

    /// The finger lifted while turning at `pixelsPerSecond`.
    mutating func release(_ pixelsPerSecond: Double, height: CGFloat) {
        let cap = 4 * Double(height)
        velocity = min(max(pixelsPerSecond, -cap), cap)
        if abs(velocity) < 120 { velocity = 0 }
    }

    /// A touch stops momentum, as on a trackpad.
    mutating func stop() {
        velocity = 0
        pending = 0
        remainder = 0
    }

    /// Whole pixels to scroll this frame.
    mutating func step(_ dt: TimeInterval) -> Int {
        var amount = 0.0
        if pending != 0 {
            let part = abs(pending) < 1 ? pending : pending * (1 - exp(-dt * 18))
            pending -= part
            amount += part
        }
        if velocity != 0 {
            amount += velocity * dt
            velocity *= exp(-dt * 2.6)
            if abs(velocity) < 20 { velocity = 0 }
        }
        remainder += amount
        // Whole pixels as they add up; once it's all been asked for, the nearest, so none are lost.
        let whole = isIdle ? remainder.rounded() : remainder.rounded(.towardZero)
        remainder = isIdle ? 0 : remainder - whole
        return Int(whole)
    }
}
