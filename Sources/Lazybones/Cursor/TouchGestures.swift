import Foundation
import simd
import SiriRemote

/// Turns a finger on the touch surface into cursor movement, or into turns around the clickpad's
/// outer ring, as tvOS does for scrubbing.
///
/// A touch that starts on the ring is held back until it shows which it is: travelling along the
/// ring makes it a turn for the rest of the touch, and moving across the ring makes it ordinary
/// movement, with what was held back caught up at once. A touch that starts inside the ring is
/// always movement.
struct TouchGestures {
    enum Output: Equatable {
        /// Finger travel since the last sample, in surface units (the surface is 1 across), y up.
        case move(SIMD2<Float>)
        /// Radians turned around the ring since the last sample; clockwise is positive.
        case turn(Float)
        /// A turn ended with the finger lifting, still turning at this many radians a second.
        case turnEnded(velocity: Float)
    }

    /// Distance from the centre where the ring starts and, a little further in, where a touch counts
    /// as having left it.
    static let ringStart: Float = 0.30
    static let ringLeave: Float = 0.20
    /// Travel before a touch on the ring is judged.
    static let judgeAfter: Float = 0.06
    /// Below this distance from the centre the angle is too jumpy to read.
    private static let tooCentral: Float = 0.1
    private static let centre = SIMD2<Float>(0.5, 0.5)

    var ringEnabled = true

    private enum State { case idle, undecided, moving, turning }
    private var state = State.idle
    private var start = SIMD2<Float>.zero
    private var last = SIMD2<Float>.zero
    private var lastTime: TimeInterval = 0
    private var turned: Float = 0
    /// Radians a second, smoothed, for momentum once the finger lifts.
    private var angularVelocity: Float = 0

    var isTurning: Bool { state == .turning }

    mutating func handle(_ sample: TouchSample) -> [Output] {
        let p = sample.position
        switch sample.phase {
        case .began:
            start = p
            last = p
            lastTime = sample.time
            turned = 0
            angularVelocity = 0
            state = ringEnabled && simd_distance(p, Self.centre) >= Self.ringStart ? .undecided : .moving
            return []
        case .moved:
            defer {
                last = p
                lastTime = sample.time
            }
            switch state {
            case .idle: return []
            case .moving: return p == last ? [] : [.move(p - last)]
            case .turning: return turn(to: p, at: sample.time).map { [.turn($0)] } ?? []
            case .undecided:
                turned += Self.angle(from: last, to: p)
                let r = simd_distance(p, Self.centre)
                if r < Self.ringLeave { return becomeMoving(at: p) }
                guard simd_distance(p, start) >= Self.judgeAfter else { return [] }
                // Along the ring or across it: the arc travelled against the change in radius.
                let along = abs(turned) * simd_distance(start, Self.centre)
                let across = abs(r - simd_distance(start, Self.centre))
                guard along > across * 1.5 else { return becomeMoving(at: p) }
                state = .turning
                return [.turn(turned)]
            }
        case .ended:
            defer { state = .idle }
            guard state == .turning else { return [] }
            // A finger that stopped before lifting leaves nothing to carry on.
            let still = sample.time - lastTime > 0.08
            return [.turnEnded(velocity: still ? 0 : angularVelocity)]
        }
    }

    private mutating func becomeMoving(at p: SIMD2<Float>) -> [Output] {
        state = .moving
        return [.move(p - start)]
    }

    private mutating func turn(to p: SIMD2<Float>, at time: TimeInterval) -> Float? {
        guard simd_distance(p, Self.centre) >= Self.tooCentral else { return nil }
        let a = Self.angle(from: last, to: p)
        let dt = Float(time - lastTime)
        if dt > 0 { angularVelocity += (a / dt - angularVelocity) * 0.35 }
        return a == 0 ? nil : a
    }

    /// The clockwise angle from `a` to `b` around the centre, in radians (-π...π).
    static func angle(from a: SIMD2<Float>, to b: SIMD2<Float>) -> Float {
        let va = a - centre, vb = b - centre
        guard simd_length(va) >= tooCentral, simd_length(vb) >= tooCentral else { return 0 }
        // y is up, so counterclockwise is positive in atan2's terms; clockwise is its negative.
        return -atan2(va.x * vb.y - va.y * vb.x, simd_dot(va, vb))
    }
}
