import AppKit
import WebKit
import XCTest
@testable import Lull

/// An Escape the page ignores must not reach the window, where macOS would read it as "exit full screen".
@MainActor
final class WebHostTests: XCTestCase {
    private final class Window: NSWindow {
        var cancels = 0
        override func cancelOperation(_ sender: Any?) { cancels += 1 }
    }

    private final class Loaded: NSObject, WKNavigationDelegate {
        var done = false
        func webView(_ w: WKWebView, didFinish _: WKNavigation!) { done = true }
    }

    private func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    /// How many times an Escape the page ignores reached the window, with `host` around the web view.
    private func escapes(reachingWindowThrough host: NSView) -> Int {
        // Off screen, so the test doesn't flash a window.
        let window = Window(contentRect: NSRect(x: -12000, y: -12000, width: 400, height: 300),
                            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let loaded = Loaded()
        webView.navigationDelegate = loaded
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        host.addSubview(webView)
        window.contentView = host
        window.orderFrontRegardless()
        webView.loadHTMLString("<html><body>nothing here uses Escape</body></html>", baseURL: nil)
        for _ in 0..<50 where !loaded.done { spin(0.1) }
        window.makeFirstResponder(webView)
        SyntheticKeys.press(.back, in: window)
        spin(0.8)
        window.orderOut(nil)
        return window.cancels
    }

    func testAPlainParentLetsAnIgnoredEscapeReachTheWindow() {
        XCTAssertEqual(escapes(reachingWindowThrough: NSView()), 1, "the premise: this is how full screen got exited")
    }

    func testTheWebHostStopsIt() {
        XCTAssertEqual(escapes(reachingWindowThrough: WebHostView()), 0)
    }
}
