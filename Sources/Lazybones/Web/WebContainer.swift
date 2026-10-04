import SwiftUI
import WebKit

/// Hosts a service's long-lived web view in SwiftUI. The view is moved in, never recreated.
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView
    /// Whether the page takes keyboard focus. Not while it's kept mounted out of sight to play on.
    var takesFocus = true

    func makeNSView(context: Context) -> NSView {
        let host = WebHostView()
        attach(to: host)
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        if webView.superview !== host {
            attach(to: host)
        } else if takesFocus {
            DispatchQueue.main.async { [webView] in
                if webView.window?.firstResponder !== webView { webView.window?.makeFirstResponder(webView) }
            }
        }
    }

    private func attach(to host: NSView) {
        webView.removeFromSuperview()
        webView.frame = host.bounds
        host.addSubview(webView)
        host.needsLayout = true
        if takesFocus { DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) } }
    }
}

/// The web view's parent in the responder chain. A key the page ignores travels up it, and an Escape
/// nobody handles reaches the window, which macOS takes to mean "leave full screen". Back sends the
/// page an Escape, so pages that don't use it (a YouTube account picker) would drop Lazybones out of full
/// screen. Handling it here, and doing nothing, stops that.
///
/// It also keeps the page out from under a window's title bar. WebKit would otherwise push the page
/// down by the title bar's height itself, and then the page's coordinates (which the cursor's
/// targets are in) would no longer be the web view's (which its mouse events are in).
final class WebHostView: NSView {
    override func cancelOperation(_ sender: Any?) {}

    override func layout() {
        super.layout()
        var frame = bounds
        if let window, window.styleMask.contains(.fullSizeContentView) {
            let visible = convert(window.contentLayoutRect, from: nil)
            frame = bounds.intersection(visible)
            if frame.isNull { frame = bounds }
        }
        for view in subviews where view.frame != frame { view.frame = frame }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }
}
