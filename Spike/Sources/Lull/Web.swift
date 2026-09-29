import AppKit
import SiriRemote
import WebKit

private let safariVersion: String =
    NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
    ?? "26.0"

// youtube.com/tv only serves the TV ("leanback") UI to TV-like user agents.
private let tvUserAgent =
    "   Mozilla/5.0 (Linux armv7l) Cobalt/23.lts.4.0-gold (unlike Gecko) v8/8.8.278.8-jit gles Starboard/15, Sony_STV_2023_PS5/ (Sony, BRAVIA, Wired)"

/// One persistent WKWebView per service, so switching back resumes where you left off.
@MainActor
final class WebPool: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private(set) var views: [String: WKWebView] = [:]
    var extensions: Extensions?
    var onReport: ((_ serviceID: String, _ key: String, _ value: String) -> Void)?
    /// Text field focus and value changes from `Scripts.keyboard`, plus "reset" when a page navigates.
    var onKeyboard: ((_ serviceID: String, _ message: [String: Any]) -> Void)?
    private var mediaVolume = (level: 1.0, muted: false)

    func view(for s: Service) -> WKWebView {
        if let v = views[s.id] { return v }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.webExtensionController = extensions?.controller
        if s.agent == .safari {
            // Appends to WebKit's real UA so it reads as the installed Safari.
            config.applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"
        }

        let ucc = config.userContentController
        ucc.add(self, name: "lull")
        ucc.add(self, name: "lullKeyboard")
        ucc.addUserScript(WKUserScript(source: Scripts.hdr, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: Scripts.probe,injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: Scripts.mediaVolume, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: Scripts.keyboard, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let module = ServiceModules.module(for: s)
        if s.spatialNav, !module.handlesNavigation {
            ucc.addUserScript(WKUserScript(source: Scripts.spatialNav, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        // The service's own hacks, applied to its web view only.
        for script in module.scripts + module.styles.map(PageScript.style) { ucc.addUserScript(script.userScript) }
        module.configure(config, for: s)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isInspectable = true  // Safari ▸ Develop ▸ <this Mac> ▸ Lull
        wv.navigationDelegate = self
        wv.uiDelegate = self
        if s.agent == .tv { wv.customUserAgent = tvUserAgent }
        module.prepare(wv, for: s)
        extensions?.register(wv)
        wv.load(URLRequest(url: module.startURL(for: s)))
        views[s.id] = wv
        return wv
    }

    func send(_ command: RemoteCommand, to s: Service) {
        guard let wv = views[s.id], let win = wv.window else { return }
        if win.firstResponder !== wv { win.makeFirstResponder(wv) }
        switch command {
        case .up: key(126, 0xF700, in: win)
        case .down: key(125, 0xF701, in: win)
        case .left: key(123, 0xF702, in: win)
        case .right: key(124, 0xF703, in: win)
        case .select: key(36, 0x0D, in: win)
        case .back: key(53, 0x1B, in: win)
        case .playPause:
            let id = s.id
            wv.evaluateJavaScript(Scripts.playPause) { [weak self] result, _ in
                self?.onReport?(id, "play/pause", "\(result ?? "error")")
            }
        default: break
        }
    }

    /// Calls `__lullKB[fn](arg)` in the page, which edits the focused field and returns its new value.
    func keyboard(_ fn: String, _ arg: Any? = nil, in s: Service, then done: ((Any?) -> Void)? = nil) {
        guard let wv = views[s.id] else { return }
        wv.callAsyncJavaScript("const kb = window.__lullKB; return kb ? kb[fn](arg) : null;",
                               arguments: ["fn": fn, "arg": arg ?? NSNull()], in: nil, in: .page) { result in
            if case let .success(v) = result { done?(v) }
        }
    }

    /// A real Return key press, so forms submit the way they would from a keyboard.
    func pressReturn(_ s: Service) {
        guard let wv = views[s.id], let win = wv.window else { return }
        if win.firstResponder !== wv { win.makeFirstResponder(wv) }
        key(36, 0x0D, in: win)
    }

    /// Lull's own volume for page media, for outputs whose volume can't be changed otherwise.
    func setMediaVolume(_ level: Double, muted: Bool) {
        mediaVolume = (level, muted)
        views.values.forEach(applyMediaVolume)
    }

    private func applyMediaVolume(to wv: WKWebView) {
        wv.evaluateJavaScript("window.__lullSetVolume && window.__lullSetVolume(\(mediaVolume.level), \(mediaVolume.muted))")
    }

    func discard(_ id: String) {
        guard let wv = views.removeValue(forKey: id) else { return }
        wv.evaluateJavaScript(Scripts.pause)
        wv.removeFromSuperview()
    }

    func pause(_ s: Service) { views[s.id]?.evaluateJavaScript(Scripts.pause) }
    func reload(_ s: Service) { views[s.id]?.reload() }

    /// Synthesized key events go through the window like real ones, so pages see trusted keydowns.
    private func key(_ code: UInt16, _ scalar: UInt32, in win: NSWindow) {
        let chars = String(Character(UnicodeScalar(scalar)!))
        let flags: NSEvent.ModifierFlags = code >= 123 ? [.function, .numericPad] : []
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let ev = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
                context: nil, characters: chars, charactersIgnoringModifiers: chars,
                isARepeat: false, keyCode: code
            ) else { continue }
            win.sendEvent(ev)
        }
    }

    private func id(of wv: WKWebView) -> String? { views.first { $0.value === wv }?.key }

    private func report(_ wv: WKWebView, _ key: String, _ value: String) {
        guard let id = id(of: wv) else { return }
        onReport?(id, key, value)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "lullKeyboard" {
            if let body = message.body as? [String: Any], let wv = message.webView, let id = id(of: wv) {
                onKeyboard?(id, body)
            }
            return
        }
        guard let body = message.body as? [String: Any],
              let k = body["k"] as? String, let v = body["v"] as? String,
              let wv = message.webView else { return }
        report(wv, k, v)
    }

    // MARK: WKNavigationDelegate / WKUIDelegate

    func webView(_ wv: WKWebView, didCommit _: WKNavigation!) {
        if let id = id(of: wv) { onKeyboard?(id, ["e": "reset"]) }
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
