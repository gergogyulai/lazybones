import Foundation
import WebKit

/// Puts sites on uBlock Origin Lite's own "no filtering" list, and takes them off again.
///
/// Denying uBO Lite a site's address keeps its scripts out, but not its network rules, which
/// WebKit applies to every web view on the controller. Its "no filtering" mode turns those off for
/// a site, and is what its popup's switch sets: a message to its background, sent from `page`.
/// The sites show in its dashboard like any other.
@MainActor
final class UnfilteredSites {
    /// The sites Lazybones put on the list, so it only ever takes off its own, never the user's.
    private static let key = "uBOLiteUnfilteredHosts"
    private let defaults = UserDefaults.standard
    private let page: ExtensionPage
    private var synced: Set<String>?

    var onStatus: ((String) -> Void)?

    init(page: ExtensionPage) { self.page = page }

    /// Makes `hosts` exactly the sites Lazybones keeps unfiltered.
    func sync(_ hosts: Set<String>, in context: WKWebExtensionContext) async {
        guard hosts != synced else { return }
        let ours = Set(defaults.stringArray(forKey: Self.key) ?? [])
        let restore = ours.subtracting(hosts)
        guard !hosts.isEmpty || !restore.isEmpty else { synced = hosts; return }

        let js = """
        const details = await send({ what: 'getFilteringModeDetails' });
        const none = new Set(details.none);
        const levels = ['none', 'basic', 'optimal', 'complete'];
        const defaultLevel = Math.max(0, levels.findIndex(k => details[k].includes('all-urls')));
        const added = [];
        for (const hostname of off) {
          if (none.has(hostname)) continue;
          await send({ what: 'setFilteringMode', hostname, level: 0 });
          added.push(hostname);
        }
        for (const hostname of restore) {
          if (none.has(hostname)) await send({ what: 'setFilteringMode', hostname, level: defaultLevel });
        }
        return added;
        """
        do {
            let added = try await page.run(js, arguments: ["off": Array(hosts), "restore": Array(restore)],
                                           in: context) as? [String] ?? []
            // Ours: what we added now, and what we added before and still want. A site the user had
            // already set to no filtering stays theirs.
            defaults.set(Array(ours.intersection(hosts).union(added)), forKey: Self.key)
            synced = hosts
            onStatus?("uBO Lite: no filtering on " + (hosts.isEmpty ? "none of the apps’ sites" : hosts.sorted().joined(separator: ", ")))
        } catch {
            onStatus?("uBO Lite: couldn’t update its no-filtering sites: \(error.localizedDescription)")
        }
    }
}
