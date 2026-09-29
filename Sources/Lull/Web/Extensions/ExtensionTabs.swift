import WebKit

// Extensions only act on web views they know as tabs, so each service is a tab in one window.

@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    var tabs: [ExtensionTab] = []
    weak var active: ExtensionTab?

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { active }
}

@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    weak var webView: WKWebView?
    unowned let window: ExtensionWindow

    init(webView: WKWebView, window: ExtensionWindow) {
        self.webView = webView
        self.window = window
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { window }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { window.tabs.firstIndex { $0 === self } ?? 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func url(for context: WKWebExtensionContext) -> URL? { webView?.url }
    func isSelected(for context: WKWebExtensionContext) -> Bool { window.active === self }
}
