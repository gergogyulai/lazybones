import Foundation
import PhoneRemote
import simd
import SiriRemote

/// What the iPhone's remote means in Siri Remote terms, so the rest of the app needn't know which
/// one it's holding. The finger on the phone becomes a finger on a touch surface, swiping step by
/// step as it travels, tilting the focused icon in between, and moving a cursor where there is one.
struct PhoneInput {
    enum Output: Equatable {
        case event(RemoteEvent)
        case touch(TouchSample)
        case rest(SIMD2<Float>?)
    }

    /// Travel per focus move while dragging, in widths of the phone's touch area: a good deal less
    /// than the Siri Remote's, as the area is about twice the size.
    static let step: Float = 0.18
    /// A quick flick shorter than a step still moves focus once.
    static let flickDistance: Float = 0.07
    static let flickTime: TimeInterval = 0.45

    private var finger: SIMD2<Float>?
    private var anchor = SIMD2<Float>.zero
    private var start = SIMD2<Float>.zero
    private var began: TimeInterval = 0
    private var stepped = false

    mutating func handle(_ event: PhoneRemote.Event, at time: TimeInterval) -> [Output] {
        switch event {
        case .button(let b): return [.event(RemoteEvent(command: Self.command(for: b), source: .press))]
        case .tap: return [.event(RemoteEvent(command: .select, source: .press))]
        case .touchBegan:
            // The phone sends travel, not position, so every touch starts in the middle.
            let p = SIMD2<Float>(0.5, 0.5)
            finger = p
            anchor = p
            start = p
            began = time
            stepped = false
            return [.touch(TouchSample(.began, p, time: time)), .rest(.zero)]
        case .touchMoved(let d):
            guard var p = finger else { return [] }
            p += d
            finger = p
            var out: [Output] = [.touch(TouchSample(.moved, p, time: time))]
            let travel = p - anchor
            if max(abs(travel.x), abs(travel.y)) >= Self.step {
                out.append(.event(RemoteEvent(command: Self.direction(travel), source: .swipe)))
                anchor = p
                stepped = true
            }
            out.append(.rest(simd_clamp((p - anchor) / Self.step, SIMD2(repeating: -1), SIMD2(repeating: 1))))
            return out
        case .touchEnded:
            guard let p = finger else { return [] }
            finger = nil
            var out: [Output] = []
            let travel = p - start
            if !stepped, time - began <= Self.flickTime, max(abs(travel.x), abs(travel.y)) >= Self.flickDistance {
                out.append(.event(RemoteEvent(command: Self.direction(travel), source: .swipe)))
            }
            return out + [.touch(TouchSample(.ended, p, time: time)), .rest(nil)]
        }
    }

    static func command(for button: PhoneRemote.Button) -> RemoteCommand {
        switch button {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .select: .select
        case .menu: .back
        case .home: .home
        case .playPause: .playPause
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .mute: .mute
        case .siri: .siri
        case .power: .power
        }
    }

    private static func direction(_ d: SIMD2<Float>) -> RemoteCommand {
        abs(d.x) > abs(d.y) ? (d.x > 0 ? .right : .left) : (d.y > 0 ? .up : .down)
    }
}
