import AppKit
import WebKit
import XCTest
@testable import Lazybones

/// YouTube's ad blocking script against responses shaped like the TV app's, in a real web view.
@MainActor
final class YouTubeAdTests: XCTestCase {
    private final class Loaded: NSObject, WKNavigationDelegate {
        var done = false
        func webView(_ w: WKWebView, didFinish _: WKNavigation!) { done = true }
    }

    private var webView: WKWebView!

    private func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    override func setUp() {
        let config = WKWebViewConfiguration()
        for script in YouTube().adBlockScripts { config.userContentController.addUserScript(script.userScript) }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), configuration: config)
        let loaded = Loaded()
        webView.navigationDelegate = loaded
        webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://www.youtube.com/tv")!)
        for _ in 0..<100 where !loaded.done { spin(0.1) }
        XCTAssertTrue(loaded.done)
    }

    override func tearDown() { webView = nil }

    /// Runs `js` as the body of an async function and returns what it returns, as JSON.
    private func run(_ js: String) -> String? {
        var result: String?, finished = false
        webView.callAsyncJavaScript("return JSON.stringify(await (async () => { \(js) })())", in: nil, in: .page) { r in
            result = try? r.get() as? String
            finished = true
        }
        for _ in 0..<100 where !finished { spin(0.02) }
        return result
    }

    private static let player = #"""
    {"videoDetails":{"videoId":"abc"},"adPlacements":[{"adPlacementRenderer":{}}],"playerAds":[{}],"adSlots":[{}],"streamingData":{"formats":[]}}
    """#

    private static let home = #"""
    {"contents":{"sectionListRenderer":{"contents":[
      {"tvMastheadRenderer":{"title":"Ad"}},
      {"shelfRenderer":{"content":{"horizontalListRenderer":{"items":[
        {"tileRenderer":{"id":1}},{"adSlotRenderer":{}},{"tileRenderer":{"id":2}}]}}}}]}}}
    """#

    func testPlayerResponsesLoseTheirAdBreaks() {
        XCTAssertEqual(run("return JSON.parse(\(literal(Self.player)))"),
                       #"{"videoDetails":{"videoId":"abc"},"streamingData":{"formats":[]}}"#)
    }

    func testHomeLosesTheMastheadAndAdTiles() {
        XCTAssertEqual(run("""
        const home = JSON.parse(\(literal(Self.home)));
        const rows = home.contents.sectionListRenderer.contents;
        return [rows.length, rows[0].shelfRenderer.content.horizontalListRenderer.items.map(i => i.tileRenderer.id)];
        """), "[1,[1,2]]")
    }

    func testFetchedJSONIsCleanedToo() {
        XCTAssertEqual(run("return Object.keys(await new Response(\(literal(Self.player))).json())"),
                       #"["videoDetails","streamingData"]"#)
    }

    func testOtherJSONIsLeftAlone() {
        XCTAssertEqual(run(#"return JSON.parse('{"ads":[1],"adPlacement":2}')"#), #"{"ads":[1],"adPlacement":2}"#)
    }

    private func literal(_ s: String) -> String {
        String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
    }
}
