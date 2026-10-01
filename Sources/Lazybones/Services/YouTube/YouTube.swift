import Foundation

struct YouTube: ServiceModule {
    let service = Service(
        id: "youtube", name: "YouTube", url: URL(string: "https://www.youtube.com/tv")!,
        tint: RGB(0.8, 0.0, 0.0), agent: .tv, spatialNav: false,
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
