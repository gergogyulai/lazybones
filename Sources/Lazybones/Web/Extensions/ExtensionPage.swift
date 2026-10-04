import Foundation
import WebKit

/// A hidden page of uBlock Origin Lite's own, for changing its settings: its background only takes
/// messages from its own pages. Loaded once and kept.
@MainActor
final class ExtensionPage: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var isLoaded = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    struct Unavailable: LocalizedError {
        var errorDescription: String? { "its pages can’t be loaded" }
    }

    /// Runs `js` as the body of an async function on the page, with `send(message)` for messaging
    /// the background, and returns what it returns.
    func run(_ js: String, arguments: [String: Any] = [:], in context: WKWebExtensionContext) async throws -> Any? {
        let wv = try page(in: context)
        if !isLoaded { await withCheckedContinuation { waiting.append($0) } }
        return try await wv.callAsyncJavaScript("const send = what => chrome.runtime.sendMessage(what);\n" + js,
                                                arguments: arguments, contentWorld: .page)
    }

    private func page(in context: WKWebExtensionContext) throws -> WKWebView {
        if let webView { return webView }
        guard let config = context.webViewConfiguration else { throw Unavailable() }
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        webView = wv
        wv.load(URLRequest(url: context.baseURL.appendingPathComponent("dashboard.html")))
        return wv
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoading() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading()
    }

    private func finishLoading() {
        isLoaded = true
        for c in waiting { c.resume() }
        waiting = []
    }
}
