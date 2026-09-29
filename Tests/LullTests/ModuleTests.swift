import XCTest
import LGTV
import MacSystem

final class LGTVTests: XCTestCase {
    func testSoundOutputNames() {
        XCTAssertEqual(TVLink.soundOutputName("external_arc"), "HDMI ARC")
        XCTAssertEqual(TVLink.soundOutputName("tv_speaker"), "TV Speakers")
        XCTAssertEqual(TVLink.soundOutputName("something_new"), "something_new")
    }

    func testConfigRoundTrips() throws {
        let c = TVConfig(name: "LG TV", host: "192.168.1.20", clientKey: "abc")
        XCTAssertEqual(try JSONDecoder().decode(TVConfig.self, from: JSONEncoder().encode(c)), c)
    }

    @MainActor func testANewLinkIsOff() {
        XCTAssertEqual(TVLink().status, .off)
    }
}

final class NetworkInfoTests: XCTestCase {
    private func wifi(rssi: Int?) -> NetworkInfo {
        var n = NetworkInfo()
        n.kind = .wifi
        n.rssi = rssi
        return n
    }

    func testSignalBars() {
        XCTAssertEqual(wifi(rssi: -50).bars, 3)
        XCTAssertEqual(wifi(rssi: -60).bars, 2)
        XCTAssertEqual(wifi(rssi: -70).bars, 1)
        XCTAssertEqual(wifi(rssi: -90).bars, 0)
    }

    func testNoBarsWithoutAReading() {
        XCTAssertNil(wifi(rssi: nil).bars)
        XCTAssertNil(wifi(rssi: 0).bars)
        var ethernet = NetworkInfo()
        ethernet.kind = .ethernet
        ethernet.rssi = -40
        XCTAssertNil(ethernet.bars)
    }

    func testTitles() {
        XCTAssertEqual(NetworkInfo().title, "Not Connected")
        var n = wifi(rssi: -50)
        XCTAssertEqual(n.title, "Wi-Fi")
        n.ssid = "Home"
        XCTAssertEqual(n.title, "Home")
    }
}
