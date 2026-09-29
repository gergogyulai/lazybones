import Foundation
import WebKit

/// Loads bundled web extensions (uBlock Origin Lite) into every service's web view.
/// Web views pick them up through `WKWebViewConfiguration.webExtensionController`.
@MainActor
final class Extensions: NSObject, WKWebExtensionControllerDelegate {
    let controller = WKWebExtensionController(configuration: .default())
    var onStatus: ((String) -> Void)?
    // Extensions only act on web views they know as tabs, so each service is a tab in one window.
    private let window = ExtensionWindow()

    override init() {
        super.init()
        controller.delegate = self
        controller.didOpenWindow(window)
    }

    func register(_ webView: WKWebView) {
        let tab = ExtensionTab(webView: webView, window: window)
        window.tabs.append(tab)
        controller.didOpenTab(tab)
    }

    func activate(_ webView: WKWebView) {
        guard let tab = window.tabs.first(where: { $0.webView === webView }), tab !== window.active else { return }
        let previous = window.active
        window.active = tab
        controller.didActivateTab(tab, previousActiveTab: previous)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [window]
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        window
    }

    func loadBundled() async {
        // Dev knob: `-extSource <dir>` loads a different unpacked extension.
        let source = UserDefaults.standard.string(forKey: "extSource").map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard let bundled = source ?? Bundle.main.resourceURL?.appendingPathComponent("uBOLite", isDirectory: true),
              FileManager.default.fileExists(atPath: bundled.path) else {
            onStatus?("uBO Lite: not bundled (run ./fetch-ubol.sh, then rebuild)")
            return
        }
        do {
            let url = try installedCopy(of: bundled)
            let ext = try await WKWebExtension(resourceBaseURL: url)
            let context = WKWebExtensionContext(for: ext)
            context.uniqueIdentifier = bundled.lastPathComponent == "uBOLite" ? "ubolite" : bundled.lastPathComponent  // stable, so its settings and storage persist
            context.isInspectable = true
            // No browser UI to prompt from, so grant everything it asks for up front.
            for p in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: p) }
            for m in ext.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: m) }
            try controller.load(context)

            // uBO Lite enables its rulesets from its background script, which WebKit otherwise
            // only starts on demand.
            if ext.hasBackgroundContent {
                context.loadBackgroundContent { [weak self] error in
                    self?.onStatus?("uBO Lite: background " + (error.map { "failed: \($0.localizedDescription)" } ?? "running"))
                }
            }
            if CommandLine.arguments.contains("--ext-debug") { debugRulesets(context) }

            let problems = ext.errors + context.errors
            onStatus?("uBO Lite \(ext.version ?? "?"): loaded" + (problems.isEmpty ? "" : ", \(problems.count) warnings"))
            for e in problems.prefix(3) { onStatus?("uBO Lite warning: \(e.localizedDescription)") }
        } catch {
            onStatus?("uBO Lite: failed: \(error.localizedDescription)")
        }
    }

    private var debugView: WKWebView?

    /// Asks the extension, from one of its own pages, which rulesets are enabled.
    private func debugRulesets(_ context: WKWebExtensionContext) {
        guard let config = context.webViewConfiguration else { onStatus?("ext-debug: no config"); return }
        let wv = WKWebView(frame: .zero, configuration: config)
        debugView = wv
        wv.load(URLRequest(url: context.baseURL.appendingPathComponent("dashboard.html")))
        Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                let js = """
                const dnr = chrome.declarativeNetRequest;
                const enabled = await dnr.getEnabledRulesets();
                const dyn = await dnr.getDynamicRules();
                const sess = dnr.getSessionRules ? await dnr.getSessionRules() : [];
                const avail = dnr.getAvailableStaticRuleCount ? await dnr.getAvailableStaticRuleCount() : '?';
                const perms = await chrome.permissions.getAll();
                if (\(CommandLine.arguments.contains("--ext-strip") ? "true" : "false")) {
                  await dnr.updateSessionRules({ removeRuleIds: sess.map(r => r.id) });
                  await dnr.updateDynamicRules({ removeRuleIds: dyn.map(r => r.id) });
                }
                const sampleSession = sess.slice(0, 2).map(r => JSON.stringify(r).slice(0, 400));
                const sampleDynamic = dyn.slice(0, 2).map(r => JSON.stringify(r).slice(0, 400));
                console.log(dyn);
                globalThis.__dyn = JSON.stringify(sess.length ? sess : dyn);
                const summary = {};
                for (const r of sess) {
                  const k = r.action.type + ' ' + Object.keys(r.condition).sort().join(',') + ' p' + (r.priority || 1);
                  summary[k] = (summary[k] || 0) + 1;
                }
                const allowAll = sess.filter(r => /allow/.test(r.action.type)).slice(0, 3).map(r => JSON.stringify(r).slice(0, 300));
                const cfg = await chrome.storage.local.get(null);
                const cfgKeys = Object.fromEntries(Object.entries(cfg).filter(([k]) => /mode|filtering|default|trusted|none/i.test(k)).map(([k, v]) => [k, JSON.stringify(v).slice(0, 200)]));
                return JSON.stringify({ enabled, dynamic: dyn.length, session: sess.length, summary, allowAll, sampleSession, sampleDynamic });
                """
                wv.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let v):
                        self?.onStatus?("ext-debug: \(v)")
                        wv.evaluateJavaScript("globalThis.__dyn") { d, _ in
                            if let d = d as? String { try? d.write(toFile: NSTemporaryDirectory() + "lull-dyn.json", atomically: true, encoding: .utf8) }
                        }
                    case .failure(let e): self?.onStatus?("ext-debug error: \(e)")
                    }
                }
            }
        }
    }

    /// Parsing the extension straight out of the signed app bundle gets the process SIGKILLed,
    /// so it's loaded from a copy in Application Support, refreshed when the bundled manifest changes.
    private func installedCopy(of bundled: URL) throws -> URL {
        let fm = FileManager.default
        let dest = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Lull/Extensions/\(bundled.lastPathComponent)", isDirectory: true)
        let manifest = "manifest.json"
        let current = fm.contents(atPath: dest.appendingPathComponent(manifest).path)
        if current == nil || current != fm.contents(atPath: bundled.appendingPathComponent(manifest).path) {
            try? fm.removeItem(at: dest)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: bundled, to: dest)
        }
        return dest
    }
}

@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    var tabs: [ExtensionTab] = []
    weak var active: ExtensionTab?

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { active }
}

@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    weak var webView: WKWebView?
    unowned let window: ExtensionWindow

    init(webView: WKWebView, window: ExtensionWindow) {
        self.webView = webView
        self.window = window
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { window }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { window.tabs.firstIndex { $0 === self } ?? 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func url(for context: WKWebExtensionContext) -> URL? { webView?.url }
    func isSelected(for context: WKWebExtensionContext) -> Bool { window.active === self }
}
