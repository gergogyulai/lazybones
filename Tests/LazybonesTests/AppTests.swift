import XCTest
@testable import Lazybones

final class LaunchOptionsTests: XCTestCase {
    func testNoArgumentsMeansDefaults() {
        XCTAssertEqual(LaunchOptions(arguments: []), LaunchOptions())
    }

    func testFlagsAndValues() {
        let o = LaunchOptions(arguments: ["--windowed", "--log", "--open", "youtube", "--open-delay", "2.5", "--remote"])
        XCTAssertTrue(o.windowed)
        XCTAssertTrue(o.log)
        XCTAssertTrue(o.remote)
        XCTAssertEqual(o.open, "youtube")
        XCTAssertEqual(o.openDelay, 2.5)
        XCTAssertFalse(o.noExtensions)
    }

    func testMissingValueAndUnknownFlagsAreIgnored() {
        let o = LaunchOptions(arguments: ["--bogus", "--open"])
        XCTAssertNil(o.open)
    }
}

@MainActor
final class DiagnosticsTests: XCTestCase {
    func testEventLogIsCapped() {
        let d = Diagnostics(visible: false, echoToStdout: false)
        for i in 0..<120 { d.log("event \(i)") }
        XCTAssertEqual(d.events.count, 50)
        XCTAssertTrue(d.events.last!.hasSuffix("event 119"))
    }

    func testVideoStatsAreReportedButNotLogged() {
        let d = Diagnostics(visible: false, echoToStdout: false)
        d.report("youtube", "video", "1080p")
        d.report("youtube", "DRM", "Widevine")
        XCTAssertEqual(d.reports["youtube"], ["video": "1080p", "DRM": "Widevine"])
        XCTAssertEqual(d.events.count, 1)
    }

    func testToggle() {
        let d = Diagnostics(visible: false, echoToStdout: false)
        d.toggle()
        XCTAssertTrue(d.isVisible)
    }
}

final class LauncherMetricsTests: XCTestCase {
    func testRowsRoundUp() {
        let m = Metrics(size: CGSize(width: 1920, height: 1080), columns: 5)
        XCTAssertEqual(m.rows(0), 0)
        XCTAssertEqual(m.rows(5), 1)
        XCTAssertEqual(m.rows(6), 2)
    }

    func testTilesFillTheRowWidth() {
        let m = Metrics(size: CGSize(width: 1920, height: 1080), columns: 5)
        let row = m.tileWidth * 5 + m.gap * 4 + m.sidePadding * 2
        XCTAssertEqual(row, 1920, accuracy: 0.001)
    }
}

final class PageScriptTests: XCTestCase {
    func testStyleSourceEscapesTheCSS() {
        let script = PageScript.style(#"a::after { content: "\"; }"#)
        XCTAssertTrue(script.source.contains(#"content: \"\\\"; }"#))
        XCTAssertFalse(script.mainFrameOnly)
    }

    func testSpatialNavIsOptional() {
        XCTAssertEqual(Scripts.shared(spatialNav: false).count + 1, Scripts.shared(spatialNav: true).count)
    }
}
