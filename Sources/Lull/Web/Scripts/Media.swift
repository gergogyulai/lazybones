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

    static let pause = "document.querySelectorAll('video').forEach(v => v.pause())"

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
