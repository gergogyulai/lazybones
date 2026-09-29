import Foundation

struct AdblockTest: ServiceModule {
    let service = Service(
        id: "adblock", name: "Ad-block test", url: URL(string: "https://adblock-tester.com")!,
        tint: RGB(0.08, 0.3, 0.15), agent: .safari, spatialNav: true,
        symbol: "shield.lefthalf.filled", tagline: "Check that uBlock Origin Lite is doing its job",
        accentTint: RGB(0.2, 0.65, 0.35), builtIn: true)

    /// Checks directly whether a well-known ad script is blocked, and reports it to the debug overlay.
    let scripts = [PageScript(source: #"""
    (() => {
      if (window.top !== window || location.host !== 'adblock-tester.com') return;
      const post = (k, v) => { try { webkit.messageHandlers.lull.postMessage({ k, v: String(v) }); } catch (_) {} };
      // Loaded as a real <script>, since blocking rules are usually scoped to resource type "script".
      const probeAd = () => {
        const el = document.createElement('script');
        el.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?lull=' + Date.now();
        el.onload = () => { post('ad request', 'allowed'); el.remove(); };
        el.onerror = () => { post('ad request', 'blocked'); el.remove(); };
        document.head.appendChild(el);
      };
      probeAd(); setInterval(probeAd, 10000);
    })();
    """#)]
}
