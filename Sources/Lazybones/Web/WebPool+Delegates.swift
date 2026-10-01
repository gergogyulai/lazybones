import WebKit

extension WebPool: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let wv = message.webView else { return }
        switch message.name {
        case PageChannel.keyboard:
            if let id = serviceID(of: wv) { onKeyboard?(id, body) }
        case PageChannel.report:
            if let k = body["k"] as? String, let v = body["v"] as? String { report(wv, k, v) }
        case PageChannel.console:
            if let id = serviceID(of: wv), let level = body["level"] as? String, let msg = body["msg"] as? String {
                onConsole?(id, level, msg)
            }
        default: break
        }
    }
}

extension WebPool: WKNavigationDelegate, WKUIDelegate {
    func webView(_ wv: WKWebView, didCommit _: WKNavigation!) {
        guard let id = serviceID(of: wv) else { return }
        onKeyboard?(id, ["e": "reset"])
        onCommit?(id)
    }

    func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
        applyMediaVolume(to: wv)
        report(wv, "page", wv.url?.absoluteString ?? "?")
        if let id = serviceID(of: wv) { onLoaded?(id) }
    }

    /// Only a load that never got as far as showing anything gets a failure screen; one that fails
    /// partway (`didFail`) has already put a page on screen.
    func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        report(wv, "load", "failed: \(error.localizedDescription)")
        guard let id = serviceID(of: wv) else { return }
        if let failure = LoadFailure(error, firstLoad: wv.backForwardList.currentItem == nil) {
            onFailed?(id, failure)
        }
        onLoaded?(id)
    }

    func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        report(wv, "load", "failed: \(error.localizedDescription)")
        if let id = serviceID(of: wv) { onLoaded?(id) }
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
