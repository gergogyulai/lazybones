import AppKit
import XCTest
@testable import Lazybones
import SiriRemote

@MainActor
final class RemoteSimulatorTests: XCTestCase {
    private var sim: RemoteSimulator!
    private var events: [RemoteEvent] = []
    private var rests: [SIMD2<Float>?] = []

    override func setUp() {
        sim = RemoteSimulator()
        sim.isVisible = true
        events = []
        rests = []
        sim.onEvent = { [unowned self] in events.append($0) }
        sim.onRest = { [unowned self] in rests.append($0) }
    }

    /// A trackpad scroll by `dx`, `dy` points of finger travel (y down), in traditional scrolling.
    private func scroll(_ dx: Int32, _ dy: Int32, phase: Int64) -> NSEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -dy, wheel2: -dx, wheel3: 0)!
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        return NSEvent(cgEvent: cg)!
    }

    func testTwoFingersSwipeOneStepPerDistanceAndTiltInBetween() throws {
        try XCTSkipIf(scroll(0, 0, phase: 1).isDirectionInvertedFromDevice, "event built with natural scrolling")
        sim.scroll(scroll(0, 20, phase: 1))   // began
        XCTAssertEqual(events, [])
        sim.scroll(scroll(0, 20, phase: 2))   // changed: 40pt, one step down
        sim.scroll(scroll(0, 80, phase: 2))   // a long drag keeps stepping
        XCTAssertEqual(events.map(\.command), [.down, .down])
        XCTAssertTrue(events.allSatisfy { $0.source == .swipe })
        let tilt = try XCTUnwrap(rests.last ?? nil)
        XCTAssertLessThan(tilt.y, 0, "fingers below the last step tilt down (y is up)")
        XCTAssertGreaterThanOrEqual(tilt.y, -1)
        sim.scroll(scroll(0, 0, phase: 4))    // ended
        XCTAssertNil(rests.last ?? nil)
    }

    func testRestIsClamped() {
        sim.rest(SIMD2(3, -0.5))
        XCTAssertEqual(rests.last, SIMD2(1, -0.5))
    }

    func testTVButtonHeldReportsAHoldAndReleasedQuicklyAPress() async throws {
        sim.tap(.home)
        XCTAssertEqual(events, [RemoteEvent(command: .home, source: .press)])
        sim.down(.home)
        try await Task.sleep(for: .milliseconds(800))
        sim.up(.home)
        XCTAssertEqual(events.last, RemoteEvent(command: .home, source: .hold))
        XCTAssertEqual(events.count, 2, "a hold isn't also a press")
    }

    func testReadoutNamesTheSourceAndCollapsesRuns() {
        sim.swipe(.left)
        sim.swipe(.left)
        sim.inject(RemoteEvent(command: .select, source: .press))
        sim.mirror(RemoteEvent(command: .back, source: .press))
        XCTAssertEqual(sim.echoes.map(\.text), ["swipe ←", "select", "back"])
        XCTAssertEqual(sim.echoes.map(\.origin), [.simulator, .control, .hardware])
        XCTAssertEqual(events.count, 3, "the real remote's events are only shown, the app has them already")
        XCTAssertTrue(sim.isDown(.back), "lit for a moment")
    }
}
