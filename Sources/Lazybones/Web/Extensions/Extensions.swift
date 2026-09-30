import Foundation
import WebKit

/// Loads bundled web extensions (uBlock Origin Lite) into every service's web view.
/// Web views pick them up through `WKWebViewConfiguration.webExtensionController`.
@MainActor
final class Extensions: NSObject, WKWebExtensionControllerDelegate {
    let controller = WKWebExtensionController(configuration: .default())
    var onStatus: ((String) -> Void)?
    private let window = ExtensionWindow()
    private let inspector = ExtensionInspector()

    override init() {
        super.init()
        controller.delegate = self
        controller.didOpenWindow(window)
    }

    // MARK: Tabs

    func register(_ webView: WKWebView) {
        let tab = ExtensionTab(webView: webView, window: window)
        window.tabs.append(tab)
        controller.didOpenTab(tab)
    }

    func unregister(_ webView: WKWebView) {
        guard let tab = window.tabs.first(where: { $0.webView === webView }) else { return }
        window.tabs.removeAll { $0 === tab }
        if window.active === tab { window.active = nil }
        controller.didCloseTab(tab, windowIsClosing: false)
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

    // MARK: Loading

    /// `inspect` reports the loaded extension's rulesets, for development.
    func loadBundled(inspect: Bool = false) async {
        // Dev knob: `-extSource <dir>` loads a different unpacked extension.
        let source = UserDefaults.standard.string(forKey: "extSource").map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard let bundled = source ?? Bundle.main.resourceURL?.appendingPathComponent("uBOLite", isDirectory: true),
              FileManager.default.fileExists(atPath: bundled.path) else {
            onStatus?("uBO Lite: not bundled (run Scripts/fetch-ubol.sh, then rebuild)")
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
                Task { [weak self] in
                    do {
                        try await context.loadBackgroundContent()
                        self?.onStatus?("uBO Lite: background running")
                    } catch {
                        self?.onStatus?("uBO Lite: background failed: \(error.localizedDescription)")
                    }
                }
            }
            if inspect { inspector.run(on: context) { [weak self] in self?.onStatus?($0) } }

            let problems = ext.errors + context.errors
            onStatus?("uBO Lite \(ext.version ?? "?"): loaded" + (problems.isEmpty ? "" : ", \(problems.count) warnings"))
            for e in problems.prefix(3) { onStatus?("uBO Lite warning: \(e.localizedDescription)") }
        } catch {
            onStatus?("uBO Lite: failed: \(error.localizedDescription)")
        }
    }

    /// Parsing the extension straight out of the signed app bundle gets the process SIGKILLed,
    /// so it's loaded from a copy in Application Support, refreshed when the bundled manifest changes.
    private func installedCopy(of bundled: URL) throws -> URL {
        let fm = FileManager.default
        let dest = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Lazybones/Extensions/\(bundled.lastPathComponent)", isDirectory: true)
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
