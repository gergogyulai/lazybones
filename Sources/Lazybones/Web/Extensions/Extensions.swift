import Foundation
import WebKit

/// A web extension that ships inside the app, under Contents/Resources/<rawValue>.
enum BundledExtension: String, CaseIterable, Identifiable {
    case uBlockOriginLite = "uBOLite"
    case sponsorBlock = "SponsorBlock"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .uBlockOriginLite: "uBlock Origin Lite"
        case .sponsorBlock: "SponsorBlock"
        }
    }

    /// For the log.
    var shortName: String { self == .uBlockOriginLite ? "uBO Lite" : name }

    /// Stable, so the extension's settings and storage persist.
    var uniqueIdentifier: String { self == .uBlockOriginLite ? "ubolite" : "sponsorblock" }

    var fetchScript: String { self == .uBlockOriginLite ? "Scripts/fetch-ubol.sh" : "Scripts/fetch-sponsorblock.sh" }

    /// Whether `s` has it switched on.
    func isOn(for s: Service) -> Bool {
        switch self {
        case .uBlockOriginLite: s.blocksAds
        case .sponsorBlock: s.skipsSponsors
        }
    }
}

/// Loads the bundled web extensions (uBlock Origin Lite, SponsorBlock) into the web views of services
/// that use them. Web views pick them up through `WKWebViewConfiguration.webExtensionController`.
///
/// A web view takes one controller, and an extension loaded into a second controller would get
/// separate storage and settings, so every extension shares one. An app that switches off an
/// extension the other apps use is kept from it by denying that extension its address, and for
/// uBlock Origin Lite, whose network rules that doesn't stop, by its own "no filtering" list.
@MainActor
final class Extensions: NSObject, ObservableObject, WKWebExtensionControllerDelegate {
    enum Status: Equatable {
        /// Not loaded at all (`--no-ext`).
        case off
        case loading
        /// Not in the app bundle: its fetch script didn't run, or failed.
        case missing
        case loaded(version: String)
        case failed(String)

        var summary: String {
            switch self {
            case .off: "Off for this session (--no-ext)"
            case .loading: "Loading…"
            case .missing: "Not included in this build"
            case let .loaded(version): "Version \(version)"
            case let .failed(reason): "Couldn’t load: \(reason)"
            }
        }
    }

    let controller = WKWebExtensionController(configuration: .default())
    var onStatus: ((String) -> Void)?
    @Published private(set) var statuses: [BundledExtension: Status] = [:]
    /// The loaded extensions, for showing their own pages.
    private(set) var contexts: [BundledExtension: WKWebExtensionContext] = [:]
    /// Addresses each extension has been denied, because the apps there switched it off.
    private var denied: [BundledExtension: Set<WKWebExtension.MatchPattern>] = [:]
    private var services: [Service] = []
    /// uBlock Origin Lite's settings that Lazybones shows itself.
    let adBlock: AdBlockOptions
    private let unfiltered: UnfilteredSites
    /// The latest change to uBlock Origin Lite's "no filtering" list, which each waits for.
    private var unfiltering: Task<Void, Never>?
    private let window = ExtensionWindow()
    private let inspector = ExtensionInspector()

    override init() {
        let page = ExtensionPage()
        adBlock = AdBlockOptions(page: page)
        unfiltered = UnfilteredSites(page: page)
        super.init()
        controller.delegate = self
        controller.didOpenWindow(window)
        unfiltered.onStatus = { [weak self] in self?.onStatus?($0) }
        adBlock.onStatus = { [weak self] in self?.onStatus?($0) }
    }

    func status(_ e: BundledExtension) -> Status { statuses[e] ?? .off }

    // MARK: Apps

    /// Whether `e` acts on `s`'s site at all: uBlock Origin Lite everywhere its filters don't break the
    /// site, SponsorBlock only on YouTube. uBlock Origin Lite's switch also covers the app's own ad
    /// blocking, so it counts even unloaded.
    func applies(_ e: BundledExtension, to s: Service) -> Bool {
        if e == .uBlockOriginLite { return ServiceModules.module(for: s).allowsAdBlocking }
        guard let ext = contexts[e]?.webExtension else { return false }
        return ext.allRequestedMatchPatterns.contains { $0.matchesAllURLs || $0.matches(s.url) }
    }

    /// Whether `s`'s web view needs the controller: some extension that acts on it is switched on.
    func isUsed(by s: Service) -> Bool {
        BundledExtension.allCases.contains { contexts[$0] != nil && $0.isOn(for: s) && applies($0, to: s) }
    }

    /// Denies each extension the addresses of apps that switched it off, unless another app at the
    /// same address uses it. Takes effect on a web view's next page load.
    func update(for services: [Service]) {
        self.services = services
        for (e, context) in contexts {
            var off = Set<String>(), on = Set<String>()
            for s in services where applies(e, to: s) {
                guard let host = s.url.host(), !host.isEmpty else { continue }
                if e.isOn(for: s) { on.insert(host) } else { off.insert(host) }
            }
            let offHosts = off.subtracting(on)
            let deny = Set(offHosts.compactMap { try? WKWebExtension.MatchPattern(string: "*://\($0)/*") })
            for pattern in denied[e, default: []].subtracting(deny) {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
            for pattern in deny.subtracting(denied[e, default: []]) {
                context.setPermissionStatus(.deniedExplicitly, for: pattern)
            }
            denied[e] = deny
            if e == .uBlockOriginLite {
                let previous = unfiltering
                unfiltering = Task { [unfiltered] in
                    await previous?.value
                    await unfiltered.sync(offHosts, in: context)
                }
            }
        }
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

    /// Loads every bundled extension. `inspect` reports uBlock Origin Lite's rulesets, for development.
    func loadBundled(inspect: Bool = false) async {
        for e in BundledExtension.allCases { statuses[e] = .loading }
        for e in BundledExtension.allCases { await load(e, inspect: inspect && e == .uBlockOriginLite) }
        update(for: services)
        // So an app opened at launch already has the filtering it asked for.
        await unfiltering?.value
        if let context = contexts[.uBlockOriginLite] { await adBlock.refresh(in: context) }
    }

    private func load(_ e: BundledExtension, inspect: Bool) async {
        let log = { [weak self] (message: String) in self?.onStatus?("\(e.shortName): \(message)") }
        // Dev knob: `-extSource <dir>` loads a different unpacked ad blocker.
        let source = e == .uBlockOriginLite
            ? UserDefaults.standard.string(forKey: "extSource").map { URL(fileURLWithPath: $0, isDirectory: true) } : nil
        guard let bundled = source ?? Bundle.main.resourceURL?.appendingPathComponent(e.rawValue, isDirectory: true),
              FileManager.default.fileExists(atPath: bundled.path) else {
            log("not bundled (run \(e.fetchScript), then rebuild)")
            statuses[e] = .missing
            return
        }
        do {
            let url = try installedCopy(of: bundled)
            let ext = try await WKWebExtension(resourceBaseURL: url)
            let context = WKWebExtensionContext(for: ext)
            context.uniqueIdentifier = bundled.lastPathComponent == e.rawValue ? e.uniqueIdentifier : bundled.lastPathComponent
            context.isInspectable = true
            // No browser UI to prompt from, so grant everything it asks for up front.
            for p in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: p) }
            for m in ext.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: m) }
            try controller.load(context)
            contexts[e] = context
            statuses[e] = .loaded(version: ext.version ?? "?")

            // uBO Lite enables its rulesets from its background script, which WebKit otherwise
            // only starts on demand.
            if ext.hasBackgroundContent {
                Task {
                    do {
                        try await context.loadBackgroundContent()
                        log("background running")
                    } catch {
                        log("background failed: \(error.localizedDescription)")
                    }
                }
            }
            if inspect { inspector.run(on: context) { [weak self] in self?.onStatus?($0) } }

            let problems = ext.errors + context.errors
            onStatus?("\(e.shortName) \(ext.version ?? "?"): loaded" + (problems.isEmpty ? "" : ", \(problems.count) warnings"))
            for p in problems.prefix(3) { log("warning: \(p.localizedDescription)") }
        } catch {
            log("failed: \(error.localizedDescription)")
            statuses[e] = .failed(error.localizedDescription)
        }
    }

    /// A web view showing the extension's own settings page, or nil if it isn't loaded or has none.
    func makeOptionsPage(for e: BundledExtension) -> WKWebView? {
        guard let context = contexts[e], let url = context.optionsPageURL,
              let config = context.webViewConfiguration else { return nil }
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isInspectable = true
        wv.load(URLRequest(url: url))
        return wv
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
