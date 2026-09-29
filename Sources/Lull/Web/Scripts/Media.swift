extension Scripts {
    /// WKWebView renders HDR video on an HDR display, but outside Safari it always answers
    /// `(video-dynamic-range: high)` with no, and sites use that query to decide whether to stream
    /// HDR at all. This answers it from `(dynamic-range: high)`, which WKWebView does report
    /// correctly. Runs in every frame, since players are often embedded.
    static let hdr = #"""
    (() => {
      if (window.__lullHDR || !window.matchMedia) return;
      window.__lullHDR = true;
      const matchMedia = window.matchMedia;
      window.matchMedia = function (query) {
        return matchMedia.call(this, String(query).replace(/video-dynamic-range/gi, 'dynamic-range'));
      };
    })();
    """#

    static let playPause = #"""
    (() => {
      const v = [...document.querySelectorAll('video')]
        .sort((a, b) => b.videoWidth * b.videoHeight - a.videoWidth * a.videoHeight)[0];
      if (!v) return 'no video';
      if (v.paused) { v.play(); return 'play'; }
      v.pause(); return 'pause';
    })()
    """#

    static let pause = "document.querySelectorAll('video, audio').forEach(m => m.pause())"

    /// Tells the app whether any media is playing, so it knows which services are making sound
    /// behind the Home Screen. Reported as `playing` = 1 or 0, only when it changes.
    static let playback = #"""
    (() => {
      if (window.top !== window || window.__lullPlayback) return;
      window.__lullPlayback = true;
      let last = null;
      const check = () => {
        const now = [...document.querySelectorAll('video, audio')].some(m => !m.paused && !m.ended) ? '1' : '0';
        if (now === last) return;
        last = now;
        try { webkit.messageHandlers.lull.postMessage({ k: 'playing', v: now }); } catch (_) {}
      };
      for (const t of ['play', 'playing', 'pause', 'ended', 'emptied'])
        document.addEventListener(t, () => setTimeout(check, 0), true);
    })();
    """#

    static let exitFullscreen = "document.exitFullscreen ? document.exitFullscreen() : document.webkitExitFullscreen && document.webkitExitFullscreen()"

    /// Back is pressed in a page that handles it itself. These two bracket the key press and answer
    /// whether the page reacted (a menu opened or closed, a route changed, fullscreen toggled), so a
    /// Back the page ignores can take you Home instead of doing nothing.
    static let watchStart = #"""
    (() => {
      const w = window.__lullWatch = { changed: false, href: location.href };
      w.observer = new MutationObserver(() => { w.changed = true; });
      // Structure and the attributes overlays use, not styles: spinners and progress bars restyle constantly.
      w.observer.observe(document, { subtree: true, childList: true, attributes: true,
        attributeFilter: ['class', 'hidden', 'open', 'aria-hidden', 'aria-expanded', 'aria-modal'] });
      document.addEventListener('fullscreenchange', () => { w.changed = true; }, { once: true });
      return true;
    })()
    """#

    static let watchEnd = #"""
    (() => {
      const w = window.__lullWatch;
      if (!w) return false;
      w.observer.disconnect();
      return w.changed || location.href !== w.href;
    })()
    """#

    /// Lull's own volume for pages, used when neither the output device nor a TV can change it.
    /// At full volume and unmuted it stays out of the way, so pages' own volume controls work.
    static let mediaVolume = #"""
    (() => {
      if (window.__lullSetVolume) return;
      let level = null, muted = false;
      const apply = m => {
        if (level !== null && Math.abs(m.volume - level) > 0.001) m.volume = level;
        if (muted && !m.muted) m.muted = true;
      };
      for (const t of ['play', 'loadedmetadata', 'volumechange'])
        document.addEventListener(t, e => { if (e.target instanceof HTMLMediaElement) apply(e.target); }, true);
      window.__lullSetVolume = (v, mute) => {
        const unmute = muted && !mute;
        level = v >= 1 ? null : v;
        muted = mute;
        document.querySelectorAll('video, audio').forEach(m => {
          if (unmute) m.muted = false;
          if (level === null) m.volume = 1;
          apply(m);
        });
      };
    })();
    """#
}
