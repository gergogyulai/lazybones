import AppKit
import SiriRemote
import WebKit

/// The names pages use to talk to the app, as `webkit.messageHandlers.<name>`.
enum PageChannel {
    /// `{ k, v }` reports for the debug overlay.
    static let report = "lazybones"
    /// Text field focus and value changes, from `Scripts.keyboard`.
    static let keyboard = "lazybonesKeyboard"
    /// `{ level, msg }` console messages and uncaught errors, from `Scripts.console`.
    static let console = "lazybonesConsole"
}

/// One persistent WKWebView per service, so switching back resumes where you left off.
///
/// Owns the web views and what happens inside them. What the pages' messages mean to the rest of
/// the app is up to whoever sets `onReport` and `onKeyboard`.
@MainActor
final class WebPool: NSObject {
    private(set) var views: [String: WKWebView] = [:]
    var extensions: Extensions?
    var onReport: ((_ serviceID: String, _ key: String, _ value: String) -> Void)?
    /// A service's page finished loading, or failed to.
    var onLoaded: ((_ serviceID: String) -> Void)?
    /// A service's page couldn't be reached, for a reason worth showing.
    var onFailed: ((_ serviceID: String, LoadFailure) -> Void)?
    /// A service's page started showing a new document.
    var onCommit: ((_ serviceID: String) -> Void)?
    /// Text field focus and value changes from `Scripts.keyboard`, plus "reset" when a page navigates.
    var onKeyboard: ((_ serviceID: String, _ message: [String: Any]) -> Void)?
    /// Something a page wrote to its console, or an uncaught error (see `Scripts.console`).
    var onConsole: ((_ serviceID: String, _ level: String, _ message: String) -> Void)?
    /// Forward everything pages log, not just warnings and errors. Applies to web views made after it's set.
    var forwardsAllConsole = false
    private var mediaVolume = (level: 1.0, muted: false)

    func view(for s: Service) -> WKWebView {
        if let v = views[s.id] { return v }

        let module = ServiceModules.module(for: s)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        // An app that uses no extension gets none at all.
        let usesExtensions = extensions?.isUsed(by: s) == true
        config.webExtensionController = usesExtensions ? extensions?.controller : nil
        BrowserIdentity.configure(config, as: s.agent)

        let ucc = config.userContentController
        ucc.add(self, name: PageChannel.report)
        ucc.add(self, name: PageChannel.keyboard)
        ucc.add(self, name: PageChannel.console)
        let navigation = ServiceModules.navigation(for: s)
        let spatialNav = navigation == .spatial
        let ownNav = spatialNav ? module.spatialNavScript.map { [PageScript(source: $0, time: .start)] } : nil
        let cursor = navigation == .cursor ? [PageScript(source: Scripts.cursorTargets, time: .start)] : []
        // The service's own hacks come last, and apply to its web view only.
        for script in Scripts.shared(spatialNav: spatialNav && ownNav == nil, pageLog: forwardsAllConsole) + (ownNav ?? [])
            + cursor + module.scripts + (s.blocksAds && module.allowsAdBlocking ? module.adBlockScripts : []) + module.styles.map(PageScript.style) {
            ucc.addUserScript(script.userScript)
        }
        module.configure(config, for: s)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isInspectable = true  // Safari ▸ Develop ▸ <this Mac> ▸ Lazybones
        wv.navigationDelegate = self
        wv.uiDelegate = self
        BrowserIdentity.apply(to: wv, as: s.agent)
        module.prepare(wv, for: s)
        if usesExtensions { extensions?.register(wv) }
        wv.load(URLRequest(url: module.startURL(for: s)))
        views[s.id] = wv
        return wv
    }

    func discard(_ id: String) {
        guard let wv = views.removeValue(forKey: id) else { return }
        wv.evaluateJavaScript(Scripts.pause)
        wv.removeFromSuperview()
        extensions?.unregister(wv)
    }

    func pause(_ s: Service) { views[s.id]?.evaluateJavaScript(Scripts.pause) }

    /// Plays or pauses what the service is playing.
    func togglePlayback(_ s: Service) {
        guard let wv = views[s.id] else { return }
        let script = ServiceModules.module(for: s).playPauseScript ?? Scripts.playPause
        wv.evaluateJavaScript(script) { [weak self] result, _ in
            self?.onReport?(s.id, "play/pause", "\(result ?? "error")")
        }
    }

    func reload(_ s: Service) { views[s.id]?.reload() }

    /// Loads again what failed to load, or the service's start page if that isn't known.
    func retry(_ s: Service, _ failure: LoadFailure) {
        let url = failure.url ?? ServiceModules.module(for: s).startURL(for: s)
        views[s.id]?.load(URLRequest(url: url))
    }

    /// A picture of the page as it is now, for the app switcher. Nil if it isn't on screen.
    func snapshot(_ s: Service, width: CGFloat = 720, then done: @escaping (NSImage?) -> Void) {
        guard let wv = views[s.id], wv.window != nil else { return done(nil) }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(width))
        wv.takeSnapshot(with: config) { image, _ in done(image) }
    }

    /// Lazybones's own volume for page media, for outputs whose volume can't be changed otherwise.
    func setMediaVolume(_ level: Double, muted: Bool) {
        mediaVolume = (level, muted)
        views.values.forEach(applyMediaVolume)
    }

    func applyMediaVolume(to wv: WKWebView) {
        wv.evaluateJavaScript("window.__lazybonesSetVolume && window.__lazybonesSetVolume(\(mediaVolume.level), \(mediaVolume.muted))")
    }

    /// Runs `js` in the service's page (as the body of an async function, so it can `await` and must
    /// `return` what it wants back) and describes the result, for the debug window and `Scripts/ctl.sh`.
    func evaluate(_ js: String, in id: String) async -> String {
        guard let wv = views[id] else { return "error: \(id) has no page" }
        // A bare expression is the common case; wrap it so it needn't say `return`.
        let body = js.contains("return") || js.contains(";") || js.contains("\n") ? js : "return (\(js));"
        do {
            let result = try await wv.callAsyncJavaScript(body, contentWorld: .page)
            return Self.describe(result)
        } catch {
            let info = (error as NSError).userInfo
            return "error: \(info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription)"
        }
    }

    private static func describe(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "undefined" }
        if let s = value as? String { return s }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let s = String(data: data, encoding: .utf8) { return s }
        return "\(value)"
    }

    func serviceID(of wv: WKWebView) -> String? { views.first { $0.value === wv }?.key }

    func report(_ wv: WKWebView, _ key: String, _ value: String) {
        guard let id = serviceID(of: wv) else { return }
        onReport?(id, key, value)
    }
}
