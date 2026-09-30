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
        webView.autoresizingMask = [.width, .height]
        host.addSubview(webView)
        if takesFocus { DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) } }
    }
}

/// The web view's parent in the responder chain. A key the page ignores travels up it, and an Escape
/// nobody handles reaches the window, which macOS takes to mean "leave full screen". Back sends the
/// page an Escape, so pages that don't use it (a YouTube account picker) would drop Lull out of full
/// screen. Handling it here, and doing nothing, stops that.
final class WebHostView: NSView {
    override func cancelOperation(_ sender: Any?) {}
}
