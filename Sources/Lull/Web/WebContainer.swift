import SwiftUI
import WebKit

/// Hosts a service's long-lived web view in SwiftUI. The view is moved in, never recreated.
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        attach(to: host)
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        if webView.superview !== host { attach(to: host) }
    }

    private func attach(to host: NSView) {
        webView.removeFromSuperview()
        webView.frame = host.bounds
        webView.autoresizingMask = [.width, .height]
        host.addSubview(webView)
        DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) }
    }
}
