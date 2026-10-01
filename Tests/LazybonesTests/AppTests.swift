import XCTest
@testable import Lazybones
import SiriRemote

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

    func testDebugFlags() {
        let o = LaunchOptions(arguments: ["--debug", "--page-log", "--control", "--fresh-settings", "--no-hw-remote"])
        XCTAssertTrue(o.debug)
        XCTAssertTrue(o.pageLog)
        XCTAssertTrue(o.control)
        XCTAssertTrue(o.freshSettings)
        XCTAssertTrue(o.noHardwareRemote)
        XCTAssertTrue(o.acceptsControl)
    }

    func testMissingValueAndUnknownFlagsAreIgnored() {
        let o = LaunchOptions(arguments: ["--bogus", "--open"])
        XCTAssertNil(o.open)
    }
}

@MainActor
final class DiagnosticsTests: XCTestCase {
    func testEventLogIsCapped() {
        let d = Diagnostics(visible: false, echoToStdout: false, maxEvents: 50)
        for i in 0..<120 { d.log("event \(i)") }
        XCTAssertEqual(d.events.count, 50)
        XCTAssertEqual(d.events.last?.message, "event 119")
        XCTAssertEqual(d.events.map(\.id), Array(70..<120))
    }

    func testVideoStatsAreReportedButNotLogged() {
        let d = Diagnostics(visible: false, echoToStdout: false)
        d.report("youtube", "video", "1080p")
        d.report("youtube", "DRM", "Widevine")
        XCTAssertEqual(d.reports["youtube"], ["video": "1080p", "DRM": "Widevine"])
        XCTAssertEqual(d.events.count, 1)
        XCTAssertEqual(d.events.first?.category, .web)
    }

    func testFailedReportsAreErrors() {
        let d = Diagnostics(visible: false, echoToStdout: false)
        d.report("netflix", "load", "failed: offline")
        XCTAssertEqual(d.events.last?.level, .error)
    }

    func testConsoleMessagesAreCountedUntilThePageResets() {
        let d = Diagnostics(visible: false, echoToStdout: false)
        d.console("drm", .error, "boom")
        d.console("drm", .warning, "careful")
        d.console("drm", .info, "fyi")
        XCTAssertEqual(d.consoleCounts["drm"]?.errors, 1)
        XCTAssertEqual(d.consoleCounts["drm"]?.warnings, 1)
        XCTAssertEqual(d.events.last?.category, .page)
        d.pageReset("drm")
        XCTAssertNil(d.consoleCounts["drm"])
    }

    func testLogLineHasTimeCategoryAndLevel() {
        let e = LogEntry(id: 0, date: Date(), category: .page, level: .error, message: "boom")
        XCTAssertTrue(e.line.hasSuffix(" page    ERROR boom"), e.line)
    }
}

final class DevCommandTests: XCTestCase {
    func testPress() {
        XCTAssertEqual(DevCommand(["press", "down"]), .press([.down], hold: false))
        XCTAssertEqual(DevCommand(["press", "HOME", "hold"]), .press([.home], hold: true))
        XCTAssertEqual(DevCommand(["press", "down", "down", "select"]), .press([.down, .down, .select], hold: false))
        XCTAssertNil(DevCommand(["press", "down", "sideways"]), "one bad name spoils the sequence")
        XCTAssertNil(DevCommand(["press", "down", "up", "hold"]), "only one button can be held")
        XCTAssertNil(DevCommand(["press"]))
    }

    func testSwipe() {
        XCTAssertEqual(DevCommand(["swipe", "left", "left"]), .swipe([.left, .left]))
        XCTAssertNil(DevCommand(["swipe", "select"]))
        XCTAssertNil(DevCommand(["swipe"]))
    }

    func testEvalJoinsWordsAndTakesATarget() {
        XCTAssertEqual(DevCommand(["eval", "document", ".title"]), .eval("document .title", in: nil))
        XCTAssertEqual(DevCommand(["eval", "@youtube", "location.href"]), .eval("location.href", in: "youtube"))
        XCTAssertNil(DevCommand(["eval", "@youtube"]))
    }

    func testOthers() {
        XCTAssertEqual(DevCommand(["open", "netflix"]), .open("netflix"))
        XCTAssertEqual(DevCommand(["log"]), .log(lines: 50))
        XCTAssertEqual(DevCommand(["log", "5"]), .log(lines: 5))
        XCTAssertEqual(DevCommand(["state"]), .state)
        XCTAssertNil(DevCommand([]))
        XCTAssertNil(DevCommand(["dance"]))
    }

    func testEveryRemoteCommandHasAName() {
        XCTAssertEqual(Set(DevCommand.buttons.values), Set(RemoteCommand.allCases))
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

    func testEveryPageGetsThePlaybackReporter() {
        XCTAssertTrue(Scripts.shared(spatialNav: false).contains { $0.source == Scripts.playback })
    }
}
