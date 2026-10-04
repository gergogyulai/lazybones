import Foundation

struct YouTube: ServiceModule {
    let service = Service(
        id: "youtube", name: "YouTube", url: URL(string: "https://www.youtube.com/tv")!,
        tint: RGB(0.8, 0.0, 0.0), agent: .tv, navigation: .keys,
        symbol: "play.rectangle.fill", tagline: "Subscriptions, music and everything in between",
        accentTint: RGB(1.0, 0.2, 0.2), builtIn: true)
    let brand: Brand? = Brand(
        logo: "youtube-logo.pdf", mark: "youtube-mark.pdf",
        plate: [RGB(hex: 0x282828), RGB(hex: 0x0F0F0F)], accent: RGB(hex: 0xFF0033),
        logoWidth: 0.66)

    /// YouTube treats every Tizen TV as low-end and serves its "limited animation" look (solid black
    /// boxes behind text, no gradients or shadows). The app's own debug switch opts back into the full UI.
    func startURL(for s: Service) -> URL {
        guard s.agent == .tv, s.url.host?.hasSuffix("youtube.com") == true,
              var c = URLComponents(url: s.url, resolvingAgainstBaseURL: false) else { return s.url }
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "env_forceFullAnimation", value: "true")]
        return c.url ?? s.url
    }

    let scripts = [PageScript(source: cobaltCapabilities, time: .start)]

    let adBlockScripts = [PageScript(source: stripAds, time: .start)]

    /// uBlock Origin Lite's YouTube rules are written for the desktop and mobile sites. The TV app
    /// gets its ads in the same JSON as everything else: ad breaks in the player response
    /// (`adPlacements`, `playerAds`, `adSlots`), and a masthead and ad tiles among the Home rows.
    /// This takes them out of every response the page parses, before the app sees them, and reports
    /// how many it has removed to the debug overlay as "ads removed".
    private static let stripAds = #"""
    (() => {
      if (window.top !== window || window.__lazybonesStripAds || !/(^|\.)youtube\.com$/.test(location.hostname)) return;
      window.__lazybonesStripAds = true;
      const post = (k, v) => { try { webkit.messageHandlers.lazybones.postMessage({ k, v: String(v) }); } catch (_) {} };

      // Player response fields that schedule ads: without them the video plays as if it had none.
      const AD_FIELDS = ['adPlacements', 'playerAds', 'adSlots'];
      // Items in a list (Home's rows, a shelf's tiles) that are ads.
      const AD_ITEMS = ['tvMastheadRenderer', 'adSlotRenderer'];
      const MENTIONS_ADS = /"(adPlacements|playerAds|adSlots|tvMastheadRenderer|adSlotRenderer)"/;

      let removed = 0;
      const strip = (node, depth) => {
        if (depth > 64 || node === null || typeof node !== 'object') return;
        if (Array.isArray(node)) {
          for (let i = node.length - 1; i >= 0; i--) {
            const item = node[i];
            if (item && typeof item === 'object' && AD_ITEMS.some(k => k in item)) { node.splice(i, 1); removed++; }
            else strip(item, depth + 1);
          }
          return;
        }
        for (const k of AD_FIELDS) if (k in node) { delete node[k]; removed++; }
        for (const k in node) strip(node[k], depth + 1);
      };
      const cleaned = new WeakSet();
      const clean = value => {
        if (value === null || typeof value !== 'object' || cleaned.has(value)) return value;
        cleaned.add(value);
        const before = removed;
        strip(value, 0);
        if (removed !== before) post('ads removed', removed);
        return value;
      };

      // Responses read as text and parsed, the TV app's usual way.
      const parse = JSON.parse;
      JSON.parse = function (text, reviver) {
        const value = parse.call(this, text, reviver);
        return typeof text === 'string' && MENTIONS_ADS.test(text) ? clean(value) : value;
      };
      // fetch(...).json(), through the parse above.
      Response.prototype.json = function () { return this.text().then(t => JSON.parse(t)); };
      // XHR with responseType 'json'.
      const response = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'response');
      if (response && response.get) {
        Object.defineProperty(XMLHttpRequest.prototype, 'response', { ...response, get() {
          const value = response.get.call(this);
          return this.responseType === 'json' ? clean(value) : value;
        } });
      }
    })();
    """#

    /// Leanback on Cobalt asks for formats with extra parameters (`width=3840; height=2160;
    /// framerate=60`, `eotf=smpte2084`, `channels=6`) and expects honest answers, including a "no"
    /// for an impossible size. WebKit ignores the parameters and says yes to everything, so the
    /// player stops trusting the answers and caps playback at 720p. This answers them like a 4K
    /// Cobalt device would, and reports each distinct query to the debug overlay as "caps".
    private static let cobaltCapabilities = #"""
    (() => {
      if (window.top !== window || window.__lazybonesCobaltCaps) return;
      window.__lazybonesCobaltCaps = true;
      const post = (k, v) => { try { webkit.messageHandlers.lazybones.postMessage({ k, v: String(v) }); } catch (_) {} };

      const MAX_W = 3840, MAX_H = 2160, MAX_FPS = 60, MAX_CHANNELS = 8;
      const hdrDisplay = () => matchMedia('(dynamic-range: high)').matches;

      // Splits off the parameters WebKit doesn't understand; null means the answer is no.
      const vet = type => {
        const [base, ...params] = String(type).split(';');
        const keep = [base];
        for (const p of params) {
          const i = p.indexOf('='), k = p.slice(0, i).trim().toLowerCase(), v = p.slice(i + 1).trim().replace(/^"|"$/g, '');
          if (i < 0) { keep.push(p); continue; }
          switch (k) {
            case 'width': if (+v > MAX_W) return null; break;
            case 'height': if (+v > MAX_H) return null; break;
            case 'framerate': if (+v > MAX_FPS) return null; break;
            case 'channels': if (+v > MAX_CHANNELS) return null; break;
            case 'eotf':
              if (/smpte2084|arib-std-b67/i.test(v) && !hdrDisplay()) return null;
              if (!/bt709|smpte2084|arib-std-b67/i.test(v)) return null;
              break;
            case 'bitrate': case 'decode-to-texture': case 'cryptoblockformat': case 'samplerate': case 'features':
              break;
            default: keep.push(p);
          }
        }
        return keep.join(';');
      };

      const seen = new Set();
      const log = (type, ok) => {
        if (seen.has(type) || seen.size > 200) return;
        seen.add(type);
        post('caps', (ok ? '✓ ' : '✗ ') + type);
      };

      for (const MS of [window.MediaSource, window.ManagedMediaSource]) {
        if (!MS || !MS.isTypeSupported) continue;
        const real = MS.isTypeSupported.bind(MS);
        MS.isTypeSupported = type => {
          const base = vet(type), ok = base !== null && real(base);
          log(type, ok);
          return ok;
        };
      }
      const canPlay = HTMLMediaElement.prototype.canPlayType;
      HTMLMediaElement.prototype.canPlayType = function (type) {
        const base = vet(type), r = base === null ? '' : canPlay.call(this, base);
        log(type, !!r);
        return r;
      };
    })();
    """#
}
