import SiriRemote
import XCTest
@testable import Lazybones

/// Telling a drag from a turn around the ring, snapping, hops, and ring scrolling.
final class CursorTests: XCTestCase {
    // MARK: Touch

    private func samples(_ points: [SIMD2<Float>], ringEnabled: Bool = true) -> [TouchGestures.Output] {
        var g = TouchGestures()
        g.ringEnabled = ringEnabled
        var out: [TouchGestures.Output] = []
        for (i, p) in points.enumerated() {
            let phase: TouchSample.Phase = i == 0 ? .began : i == points.count - 1 ? .ended : .moved
            out += g.handle(TouchSample(phase, p, time: Double(i) / 100))
        }
        return out
    }

    /// Points around the ring, clockwise from the top by `degrees`, with y up.
    private func arc(_ degrees: Float, radius: Float = 0.42, steps: Int = 20) -> [SIMD2<Float>] {
        (0...steps).map { i in
            let a = Float.pi / 2 - degrees * .pi / 180 * Float(i) / Float(steps)
            return SIMD2(0.5 + radius * cos(a), 0.5 + radius * sin(a))
        }
    }

    private func moved(_ out: [TouchGestures.Output]) -> SIMD2<Float> {
        out.reduce(.zero) { if case let .move(d) = $1 { $0 + d } else { $0 } }
    }

    private func turned(_ out: [TouchGestures.Output]) -> Float {
        out.reduce(0) { if case let .turn(a) = $1 { $0 + a } else { $0 } }
    }

    func testADragFromTheMiddleMoves() {
        let out = samples([SIMD2(0.5, 0.5), SIMD2(0.55, 0.5), SIMD2(0.6, 0.52), SIMD2(0.6, 0.52)])
        XCTAssertEqual(moved(out).x, 0.1, accuracy: 0.001)
        XCTAssertEqual(moved(out).y, 0.02, accuracy: 0.001)
        XCTAssertEqual(turned(out), 0)
    }

    func testRunningAroundTheRingTurnsClockwiseAsPositive() {
        let out = samples(arc(90) + [arc(90).last!])
        XCTAssertEqual(turned(out), .pi / 2, accuracy: 0.02, "all of it, including what was held back while deciding")
        XCTAssertEqual(moved(out), .zero, "a turn doesn't also move the cursor")
        XCTAssertEqual(turned(samples(arc(-60) + [arc(-60).last!])), -.pi / 3, accuracy: 0.02)
    }

    func testATouchOnTheRingThatHeadsInwardMovesAndCatchesUp() {
        let path: [SIMD2<Float>] = [SIMD2(0.9, 0.5), SIMD2(0.85, 0.5), SIMD2(0.8, 0.5), SIMD2(0.7, 0.5), SIMD2(0.6, 0.5), SIMD2(0.6, 0.5)]
        let out = samples(path)
        XCTAssertEqual(turned(out), 0)
        XCTAssertEqual(moved(out).x, -0.3, accuracy: 0.001, "nothing lost while it was held back")
    }

    func testWithRingScrollingOffTheRingIsJustSurface() {
        let out = samples(arc(90) + [arc(90).last!], ringEnabled: false)
        XCTAssertEqual(turned(out), 0)
        XCTAssertNotEqual(moved(out), .zero)
    }

    func testAFlickAroundTheRingEndsWithItsSpeed() {
        var g = TouchGestures()
        let points = arc(120)
        var ended: Float?
        for (i, p) in points.enumerated() {
            for o in g.handle(TouchSample(i == 0 ? .began : .moved, p, time: Double(i) / 100)) {
                if case let .turnEnded(v) = o { ended = v }
            }
        }
        for o in g.handle(TouchSample(.ended, points.last!, time: Double(points.count) / 100)) {
            if case let .turnEnded(v) = o { ended = v }
        }
        // 120° over 0.2s is about 10 radians a second.
        XCTAssertEqual(ended ?? 0, 10.5, accuracy: 1.5)
    }

    // MARK: Snapping

    private let button = CGRect(x: 100, y: 100, width: 80, height: 40)

    private func motion(_ snapping: CursorSettings.Snapping, at p: CGPoint, targets: [CGRect]? = nil) -> CursorMotion {
        var m = CursorMotion()
        m.settings.snapping = snapping
        m.targets = targets ?? [button]
        m.place(at: p)
        return m
    }

    func testWithoutSnappingItGoesExactlyWhereItIsPut() {
        let m = motion(.off, at: CGPoint(x: 110, y: 105))
        XCTAssertEqual(m.snap.point, CGPoint(x: 110, y: 105))
        XCTAssertEqual(m.snap.target, button, "it still knows what it's over")
    }

    func testSnappingDrawsItTowardTheMiddleOfAButton() {
        let p = CGPoint(x: 110, y: 105)
        let light = motion(.light, at: p).snap.point
        let medium = motion(.medium, at: p).snap.point
        let hard = motion(.hard, at: p).snap.point
        XCTAssertGreaterThan(light.x, p.x)
        XCTAssertGreaterThan(medium.x, light.x)
        XCTAssertEqual(hard, CGPoint(x: button.midX, y: button.midY))
    }

    func testStrongerSnappingReachesFurther() {
        let near = CGPoint(x: 90, y: 120)   // 10 points left of the button
        XCTAssertNil(motion(.light, at: near).snap.target)
        XCTAssertEqual(motion(.medium, at: near).snap.target, button)
        let far = CGPoint(x: 75, y: 120)    // 25 points off
        XCTAssertNil(motion(.medium, at: far).snap.target)
        XCTAssertEqual(motion(.hard, at: far).snap.target, button)
        XCTAssertTrue(button.contains(motion(.medium, at: near).snap.point), "clicks land on the button it snapped to")
    }

    func testABigCardIsPointedWithinRatherThanPulledTo() {
        let card = CGRect(x: 100, y: 100, width: 480, height: 270)
        let p = CGPoint(x: 150, y: 150)
        let m = motion(.hard, at: p, targets: [card])
        XCTAssertEqual(m.snap.target, card)
        XCTAssertEqual(m.snap.point, p)
    }

    func testAButtonOnACardWinsOverTheCard() {
        let card = CGRect(x: 0, y: 0, width: 300, height: 200)
        let m = motion(.medium, at: CGPoint(x: 120, y: 110), targets: [card, button])
        XCTAssertEqual(m.snap.target, button)
    }

    // MARK: The clickpad

    func testWithSnappingAClickHopsToTheNextButtonThatWay() {
        let row = (0..<4).map { CGRect(x: 100 + $0 * 200, y: 500, width: 120, height: 60) }
        var m = motion(.medium, at: CGPoint(x: 160, y: 530), targets: row + [CGRect(x: 300, y: 800, width: 120, height: 60)])
        XCTAssertEqual(m.nudge(.right), 0)
        XCTAssertEqual(m.snap.target, row[1])
        _ = m.nudge(.right)
        XCTAssertEqual(m.snap.target, row[2], "from the button it's on, not from where it started")
        _ = m.nudge(.down)
        XCTAssertEqual(m.snap.target?.minY, 800)
    }

    func testMediumSnappingOnlyHopsHalfAScreen() {
        let far = CGRect(x: 1700, y: 500, width: 100, height: 60)
        var medium = motion(.medium, at: CGPoint(x: 100, y: 530), targets: [far])
        _ = medium.nudge(.right)
        XCTAssertNil(medium.snap.target, "too far: it steps instead")
        XCTAssertGreaterThan(medium.raw.x, 100)
        var hard = motion(.hard, at: CGPoint(x: 100, y: 530), targets: [far])
        _ = hard.nudge(.right)
        XCTAssertEqual(hard.snap.target, far)
    }

    func testWithoutSnappingAClickSteps() {
        var m = motion(.off, at: CGPoint(x: 500, y: 500))
        _ = m.nudge(.left)
        XCTAssertEqual(m.raw.y, 500)
        XCTAssertLessThan(m.raw.x, 500)
    }

    func testPushingPastTheBottomScrolls() {
        var m = motion(.off, at: CGPoint(x: 500, y: 1079))
        XCTAssertGreaterThan(m.nudge(.down), 0)
        XCTAssertEqual(m.nudge(.up), 0, "not at the top: it just moves")
        var top = motion(.off, at: CGPoint(x: 500, y: 0))
        XCTAssertLessThan(top.nudge(.up), 0)
        var glide = motion(.off, at: CGPoint(x: 500, y: 1070))
        XCTAssertGreaterThan(glide.glide(.down, held: 1, dt: 0.1), 0)
        XCTAssertEqual(glide.raw.y, 1079)
    }

    func testHoldingGathersSpeed() {
        var m = motion(.off, at: CGPoint(x: 100, y: 500))
        _ = m.glide(.right, held: 0, dt: 0.01)
        let early = m.raw.x - 100
        let before = m.raw.x
        _ = m.glide(.right, held: 1.5, dt: 0.01)
        XCTAssertGreaterThan(m.raw.x - before, early * 2)
    }

    func testFasterTouchGoesFurther() {
        var slow = motion(.off, at: CGPoint(x: 500, y: 500))
        for _ in 0..<20 { _ = slow.touchMove(SIMD2(0.001, 0), dt: 0.01) }
        var fast = motion(.off, at: CGPoint(x: 500, y: 500))
        _ = fast.touchMove(SIMD2(0.02, 0), dt: 0.005)
        // The same 0.02 of the surface either way.
        XCTAssertGreaterThan(fast.raw.x - 500, (slow.raw.x - 500) * 1.5)
    }

    func testTouchSpeedSettingScales() {
        var normal = motion(.off, at: CGPoint(x: 500, y: 500))
        _ = normal.touchMove(SIMD2(0.01, 0), dt: 0.01)
        var quick = motion(.off, at: CGPoint(x: 500, y: 500))
        quick.settings.touchSpeed = 1
        _ = quick.touchMove(SIMD2(0.01, 0), dt: 0.01)
        XCTAssertEqual((quick.raw.x - 500) / (normal.raw.x - 500), 4, accuracy: 0.01)
    }

    // MARK: Scrolling

    private func drain(_ s: inout RingScroll, seconds: Double = 3) -> Int {
        var total = 0
        for _ in 0..<Int(seconds * 120) { total += s.step(1 / 120) }
        return total
    }

    func testATurnScrollsAllOfItSmoothly() {
        let settings = CursorSettings()
        var s = RingScroll()
        let pixels = RingScroll.pixels(.pi, height: 1000, settings: settings)
        XCTAssertEqual(pixels, 600, accuracy: 0.01, "half a turn, a bit over half a page")
        s.add(pixels)
        let first = s.step(1 / 120)
        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThan(first, 600, "eased out, not all at once")
        XCTAssertEqual(first + drain(&s), 600)
        XCTAssertTrue(s.isIdle)
    }

    func testScrollDirectionAndSpeed() {
        var settings = CursorSettings()
        settings.scrollDirection = .clockwiseUp
        XCTAssertLessThan(RingScroll.pixels(1, height: 1000, settings: settings), 0)
        settings.scrollSpeed = 0
        XCTAssertEqual(RingScroll.pixels(-1, height: 1000, settings: settings),
                       RingScroll.pixels(1, height: 1000, settings: CursorSettings()) / 4, accuracy: 0.01)
    }

    func testMomentumCarriesOnAndStops() {
        var s = RingScroll()
        s.release(3000, height: 1000)
        let carried = drain(&s)
        XCTAssertGreaterThan(carried, 500)
        XCTAssertTrue(s.isIdle)
        s.release(3000, height: 1000)
        _ = s.step(1 / 120)
        s.stop()
        XCTAssertEqual(drain(&s), 0, "a touch stops it")
    }

    // MARK: Settings

    func testNavigationFromBeforeThereWereThreeModes() throws {
        func decode(_ spatial: String) throws -> Service {
            try JSONDecoder().decode(Service.self, from: Data(#"""
            {"id": "x", "name": "X", "url": "https://example.com", "tint": {"r": 0, "g": 0, "b": 0},
             "agent": "safari", \#(spatial)}
            """#.utf8))
        }
        XCTAssertEqual(try decode(#""spatialNav": true"#).navigation, .spatial)
        XCTAssertEqual(try decode(#""spatialNav": false"#).navigation, .keys)
        let s = try decode(#""navigation": "cursor", "cursor": {"snapping": "hard", "someday": 1}"#)
        XCTAssertEqual(s.navigation, .cursor)
        XCTAssertEqual(s.cursor.snapping, .hard)
        XCTAssertEqual(s.cursor.touchSpeed, CursorSettings().touchSpeed)
    }

    func testCursorSettingsRoundTrip() throws {
        var s = Service.custom()
        s.navigation = .cursor
        s.cursor.scrollDirection = .clockwiseUp
        s.cursor.size = .large
        let back = try JSONDecoder().decode(Service.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testSitesWithTheirOwnNavigationKeepIt() {
        var jellyfin = Service.defaults.first { $0.id == "jellyfin" }!
        jellyfin.navigation = .cursor
        XCTAssertEqual(ServiceModules.navigation(for: jellyfin), .keys)
        var custom = Service.custom()
        custom.navigation = .cursor
        XCTAssertEqual(ServiceModules.navigation(for: custom), .cursor)
    }
}
