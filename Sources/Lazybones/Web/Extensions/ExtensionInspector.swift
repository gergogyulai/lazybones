import WebKit

/// Development aid (`--ext-debug`): asks the extension, from one of its own pages, which
/// rulesets are enabled and how many dynamic and session rules it holds.
@MainActor
final class ExtensionInspector {
    private var webView: WKWebView?

    func run(on context: WKWebExtensionContext, report: @escaping (String) -> Void) {
        guard let config = context.webViewConfiguration else { report("ext-debug: no web view configuration"); return }
        let wv = WKWebView(frame: .zero, configuration: config)
        webView = wv
        wv.load(URLRequest(url: context.baseURL.appendingPathComponent("dashboard.html")))
        // Give the extension time to set itself up.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            let js = """
            const dnr = chrome.declarativeNetRequest;
            const [enabled, dynamic, session] = await Promise.all([
              dnr.getEnabledRulesets(), dnr.getDynamicRules(), dnr.getSessionRules?.() ?? []]);
            return JSON.stringify({ enabled, dynamic: dynamic.length, session: session.length });
            """
            wv.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case let .success(v): report("ext-debug: \(v)")
                case let .failure(e): report("ext-debug error: \(e.localizedDescription)")
                }
                self?.webView = nil
            }
        }
    }
}
