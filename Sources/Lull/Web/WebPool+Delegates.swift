import WebKit

extension WebPool: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let wv = message.webView else { return }
        switch message.name {
        case PageChannel.keyboard:
            if let id = serviceID(of: wv) { onKeyboard?(id, body) }
        case PageChannel.report:
            if let k = body["k"] as? String, let v = body["v"] as? String { report(wv, k, v) }
        default: break
        }
    }
}

extension WebPool: WKNavigationDelegate, WKUIDelegate {
    func webView(_ wv: WKWebView, didCommit _: WKNavigation!) {
        if let id = serviceID(of: wv) { onKeyboard?(id, ["e": "reset"]) }
    }

    func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
        applyMediaVolume(to: wv)
        report(wv, "page", wv.url?.absoluteString ?? "?")
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        report(wv, "load", "failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ wv: WKWebView) {
        report(wv, "load", "web process crashed, reloading")
        wv.reload()
    }

    // Keep popups (login flows) in the same view.
    func webView(_ wv: WKWebView, createWebViewWith _: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        wv.load(action.request)
        return nil
    }
}
