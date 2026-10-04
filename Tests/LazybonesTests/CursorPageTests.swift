import AppKit
import WebKit
import XCTest
@testable import Lazybones

/// The cursor's way into a page, in a real web view: clicks and hovers arrive as trusted mouse
/// events on the element under the point, the wheel scrolls what's under it, and the page lists
/// what can be clicked, leaving out what a dialog covers.
@MainActor
final class CursorPageTests: XCTestCase {
    private static let page = """
    <html><body style="margin:0;height:3000px">
    <style>#go:hover{outline:3px solid red}</style>
    <button id="go" style="position:absolute;left:40px;top:40px;width:120px;height:50px">Go</button>
    <div id="box" style="position:absolute;left:40px;top:150px;width:300px;height:200px;overflow:auto">
      <div style="height:2000px"></div>
    </div>
    <div id="card" style="position:absolute;left:400px;top:40px;width:200px;height:120px;cursor:pointer">
      <span>inherits the pointer, so it isn't listed again</span>
    </div>
    <a id="hidden" href="#" style="position:absolute;left:400px;top:300px;width:100px;height:40px;display:block">under</a>
    <div style="position:absolute;left:380px;top:280px;width:200px;height:100px;background:#000"></div>
    <script>
    window.events = [];
    for (const t of ['mouseover', 'mousedown', 'mouseup', 'click'])
      document.addEventListener(t, e => events.push(t + ':' + e.isTrusted + ':' + (e.target.id || e.target.tagName)), true);
    </script>
    </body></html>
    """

    private final class Loaded: NSObject, WKNavigationDelegate {
        var done = false
        func webView(_ w: WKWebView, didFinish _: WKNavigation!) { done = true }
    }

    private var window: NSWindow!
    private var web: WebPool!
    private var service: Service!
    private var webView: WKWebView!

    private func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func run(_ js: String) -> Any? {
        var result: Any?, finished = false
        webView.evaluateJavaScript(js) { r, _ in result = r; finished = true }
        for _ in 0..<100 where !finished { spin(0.02) }
        return result
    }

    /// Loads the page in a `WebPool` web view, with the scripts a cursor app gets.
    private func load() {
        var s = Service.custom()
        s.url = URL(string: "about:blank")!
        s.navigation = .cursor
        service = s
        web = WebPool()
        webView = web.view(for: s)
        // Off screen, so the test doesn't flash a window.
        window = NSWindow(contentRect: NSRect(x: -12000, y: -12000, width: 800, height: 500),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        webView.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        window.contentView = webView
        window.orderFrontRegardless()
        let loaded = Loaded()
        webView.navigationDelegate = loaded
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://example.com/"))
        for _ in 0..<50 where !loaded.done { spin(0.1) }
        // Input that arrives the moment a page has loaded can be dropped before the page takes any.
        spin(0.3)
    }

    override func tearDown() {
        window?.orderOut(nil)
        if let service { web?.discard(service.id) }
        window = nil
    }

    func testAClickIsATrustedClickOnWhatsUnderThePoint() {
        load()
        let p = CGPoint(x: 100, y: 65)
        web.click(at: p, in: service)
        spin(0.4)
        let events = run("events.join(' ')") as? String ?? ""
        for e in ["mouseover:true:go", "mousedown:true:go", "mouseup:true:go", "click:true:go"] {
            XCTAssertTrue(events.contains(e), "\(e) in \(events)")
        }
    }

    func testTheWheelScrollsWhatsUnderThePoint() {
        load()
        web.scroll(dx: 0, dy: 120, at: CGPoint(x: 150, y: 250), in: service)
        spin(0.5)
        XCTAssertEqual(run("document.getElementById('box').scrollTop") as? Int, 120)
        XCTAssertEqual(run("scrollY") as? Int, 0, "not the page behind it")
        web.scroll(dx: 0, dy: 200, at: CGPoint(x: 700, y: 450), in: service)
        spin(0.5)
        XCTAssertEqual(run("scrollY") as? Int, 200)
    }

    func testThePageListsWhatCanBeClicked() {
        load()
        var targets: [CGRect]?
        web.pointerTargets(in: service) { targets = $0 }
        for _ in 0..<50 where targets == nil { spin(0.02) }
        let rects = targets ?? []
        XCTAssertTrue(rects.contains(CGRect(x: 40, y: 40, width: 120, height: 50)), "the button: \(rects)")
        XCTAssertTrue(rects.contains(CGRect(x: 400, y: 40, width: 200, height: 120)), "a plain element with a pointer cursor")
        XCTAssertFalse(rects.contains { $0.minX == 400 && $0.minY == 300 }, "the link something covers")
        XCTAssertEqual(rects.filter { $0.intersects(CGRect(x: 400, y: 40, width: 200, height: 120)) }.count, 1,
                       "the card once, not again for its child")
    }
}
