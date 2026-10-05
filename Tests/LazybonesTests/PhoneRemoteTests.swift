import PhoneRemote
import SiriRemote
import XCTest
@testable import Lazybones

final class PhoneRemoteTests: XCTestCase {
    private func events(_ outputs: [PhoneInput.Output]) -> [RemoteEvent] {
        outputs.compactMap { if case .event(let e) = $0 { e } else { nil } }
    }

    func testTheIdentityIsLazybonesAndFourCharacters() {
        let id = PhoneRemote.Identity.generate()
        XCTAssertTrue(id.name.hasPrefix("Lazybones "))
        XCTAssertEqual(id.name.count, "Lazybones ".count + 4)
        XCTAssertNotNil(UUID(uuidString: id.serverID))
        let mac = id.deviceID.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        XCTAssertEqual(mac.count, 6)
        // Locally administered and unicast, so it can't be a real device's.
        XCTAssertEqual(mac[0] & 0x03, 0x02)
    }

    func testTheIdentityIsKeptWithTheSettings() throws {
        var s = LauncherSettings()
        s.phoneRemoteIdentity = .generate()
        let back = try JSONDecoder().decode(LauncherSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.phoneRemoteIdentity, s.phoneRemoteIdentity)
    }

    func testButtonsAreRemoteCommands() {
        var input = PhoneInput()
        XCTAssertEqual(events(input.handle(.button(.menu), at: 0)), [RemoteEvent(command: .back, source: .press)])
        XCTAssertEqual(events(input.handle(.button(.playPause), at: 0)), [RemoteEvent(command: .playPause, source: .press)])
        XCTAssertEqual(events(input.handle(.tap, at: 0)), [RemoteEvent(command: .select, source: .press)])
    }

    func testALongDragStepsAsItTravels() {
        var input = PhoneInput()
        _ = input.handle(.touchBegan, at: 0)
        var swipes: [RemoteEvent] = []
        for i in 1...10 {
            swipes += events(input.handle(.touchMoved(SIMD2(PhoneInput.step / 2, 0)), at: Double(i) / 10))
        }
        swipes += events(input.handle(.touchEnded, at: 1.1))
        XCTAssertEqual(swipes, Array(repeating: RemoteEvent(command: .right, source: .swipe), count: 5))
    }

    func testAQuickFlickMovesOnce() {
        var input = PhoneInput()
        _ = input.handle(.touchBegan, at: 0)
        XCTAssertEqual(events(input.handle(.touchMoved(SIMD2(0, PhoneInput.flickDistance * 1.2)), at: 0.1)), [])
        XCTAssertEqual(events(input.handle(.touchEnded, at: 0.2)), [RemoteEvent(command: .up, source: .swipe)])
    }

    func testASlowShortDragDoesNothing() {
        var input = PhoneInput()
        _ = input.handle(.touchBegan, at: 0)
        _ = input.handle(.touchMoved(SIMD2(0, -PhoneInput.flickDistance)), at: 0.4)
        XCTAssertEqual(events(input.handle(.touchEnded, at: 1)), [])
    }

    func testTheFingerIsFollowedForTheCursor() {
        var input = PhoneInput()
        let began = input.handle(.touchBegan, at: 0)
        XCTAssertEqual(began.first, .touch(TouchSample(.began, SIMD2(0.5, 0.5), time: 0)))
        let moved = input.handle(.touchMoved(SIMD2(0.01, -0.02)), at: 0.1)
        XCTAssertEqual(moved.first, .touch(TouchSample(.moved, SIMD2(0.51, 0.48), time: 0.1)))
        XCTAssertEqual(input.handle(.touchEnded, at: 0.6).last, .rest(nil))
    }
}
