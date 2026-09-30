import AppKit
import SiriRemote
import WebKit

/// The names pages use to talk to the app, as `webkit.messageHandlers.<name>`.
enum PageChannel {
    /// `{ k, v }` reports for the debug overlay.
    static let report = "lazybones"
    /// Text field focus and value changes, from `Scripts.keyboard`.
    static let keyboard = "lazybonesKeyboard"
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
    /// Text field focus and value changes from `Scripts.keyboard`, plus "reset" when a page navigates.
    var onKeyboard: ((_ serviceID: String, _ message: [String: Any]) -> Void)?
    private var mediaVolume = (level: 1.0, muted: false)

    func view(for s: Service) -> WKWebView {
        if let v = views[s.id] { return v }

        let module = ServiceModules.module(for: s)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.webExtensionController = extensions?.controller
        BrowserIdentity.configure(config, as: s.agent)

        let ucc = config.userContentController
        ucc.add(self, name: PageChannel.report)
        ucc.add(self, name: PageChannel.keyboard)
        let spatialNav = s.spatialNav && !module.handlesNavigation
        let ownNav = spatialNav ? module.spatialNavScript.map { [PageScript(source: $0, time: .start)] } : nil
        // The service's own hacks come last, and apply to its web view only.
        for script in Scripts.shared(spatialNav: spatialNav && ownNav == nil) + (ownNav ?? [])
            + module.scripts + module.styles.map(PageScript.style) {
            ucc.addUserScript(script.userScript)
        }
        module.configure(config, for: s)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isInspectable = true  // Safari ▸ Develop ▸ <this Mac> ▸ Lazybones
        wv.navigationDelegate = self
        wv.uiDelegate = self
        BrowserIdentity.apply(to: wv, as: s.agent)
        module.prepare(wv, for: s)
        extensions?.register(wv)
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

    func serviceID(of wv: WKWebView) -> String? { views.first { $0.value === wv }?.key }

    func report(_ wv: WKWebView, _ key: String, _ value: String) {
        guard let id = serviceID(of: wv) else { return }
        onReport?(id, key, value)
    }
}
