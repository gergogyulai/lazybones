import SwiftUI
import WebKit

/// Hosts a service's long-lived web view in SwiftUI. The view is moved in, never recreated.
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView
    /// Whether the page takes keyboard focus. Not while it's kept mounted out of sight to play on.
    var takesFocus = true

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
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
