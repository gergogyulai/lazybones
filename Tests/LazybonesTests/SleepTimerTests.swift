import LGTV
import XCTest
@testable import Lazybones

@MainActor
final class SleepTimerTests: XCTestCase {
    func testAClickTurnsItOnAtTheDefaultAndOffAgain() {
        let t = SleepTimer()
        t.toggle()
        XCTAssertTrue(t.isOn)
        XCTAssertEqual(t.minutes, SleepTimer.defaultMinutes)
        t.toggle()
        XCTAssertFalse(t.isOn)
    }

    func testRightFromOffStartsAtTheShortestAndStopsAtTheLongest() {
        let t = SleepTimer()
        t.step(1)
        XCTAssertEqual(t.minutes, SleepTimer.presets.first)
        for _ in SleepTimer.presets { t.step(1) }
        XCTAssertEqual(t.minutes, SleepTimer.presets.last)
        XCTAssertTrue(t.isOn)
    }

    func testLeftFromTheShortestTurnsItOff() {
        let t = SleepTimer()
        t.step(1)
        t.step(-1)
        XCTAssertFalse(t.isOn)
        t.step(-1)
        XCTAssertFalse(t.isOn)
    }

    func testAClickAfterStepsComesBackToTheLastLength() {
        let t = SleepTimer()
        t.start(90)
        t.toggle()
        t.toggle()
        XCTAssertEqual(t.minutes, 90)
        XCTAssertTrue(t.isOn)
    }

    func testItFiresOnceAndTurnsOff() async throws {
        let t = SleepTimer()
        var fired = 0
        t.onFire = { fired += 1 }
        t.schedule(after: 0.05)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fired, 1)
        XCTAssertFalse(t.isOn)
    }

    func testCancellingStopsItFiring() async throws {
        let t = SleepTimer()
        var fired = false
        t.onFire = { fired = true }
        t.schedule(after: 0.05)
        t.cancel()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(fired)
    }

    func testLabelRoundsUp() {
        XCTAssertEqual(SleepTimer.label(remaining: 29 * 60 + 1), "30 min left")
        XCTAssertEqual(SleepTimer.label(remaining: 60), "1 min left")
        XCTAssertEqual(SleepTimer.label(remaining: 59), "Less than a minute")
    }

    func testControlCenterStepsAndTogglesTheTimer() {
        let tv = TVLink()
        let t = SleepTimer()
        let cc = ControlCenter(audio: VolumeRouter(tv: tv) { _, _ in }, tv: tv, sleepTimer: t)
        cc.focus = .sleepTimer
        _ = cc.handle(.right)
        XCTAssertEqual(t.minutes, SleepTimer.presets.first)
        _ = cc.handle(.select)
        XCTAssertFalse(t.isOn)
        _ = cc.handle(.down)
        XCTAssertNotEqual(cc.focus, .sleepTimer)
        _ = cc.handle(.up)
        XCTAssertEqual(cc.focus, .sleepTimer)
    }
}
