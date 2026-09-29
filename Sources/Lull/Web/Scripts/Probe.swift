extension Scripts {
    /// Reports DRM/EME support and live video state (codec, HDR, audio, key system, fps, buffer)
    /// back to the app via `webkit.messageHandlers.lull`. Injected at document start so its MSE and
    /// EME hooks are in place before any player script runs.
    static let probe = #"""
    (() => {
      if (window.top !== window) return;
      const post = (k, v) => { try { webkit.messageHandlers.lull.postMessage({ k, v: String(v) }); } catch (_) {} };

      const check = (keySystem, label, initDataTypes) => {
        if (!navigator.requestMediaKeySystemAccess) return post(label, 'no EME API');
        const cfg = [{ initDataTypes, videoCapabilities: [{ contentType: 'video/mp4; codecs="avc1.640028"' }] }];
        navigator.requestMediaKeySystemAccess(keySystem, cfg)
          .then(() => post(label, 'yes'), e => post(label, 'no (' + e.name + ')'));
      };
      check('com.apple.fps', 'EME FairPlay', ['sinf', 'skd']);
      check('com.widevine.alpha', 'EME Widevine', ['cenc']);
      post('MSE', window.MediaSource ? 'yes' : (window.ManagedMediaSource ? 'managed only' : 'no'));

      document.addEventListener('encrypted', e => post('encrypted', 'yes (' + e.initDataType + ')'), true);
      document.addEventListener('error', e => {
        if (!(e.target instanceof HTMLMediaElement)) return;
        const m = e.target.error;
        post('video error', m ? m.code + ' ' + (m.message || '') : '?');
      }, true);

      // Codec strings the page hands to MSE, per MediaSource, so the playing video's can be found.
      // Wrapped before any page script runs (this is injected at document start).
      const sources = new Map(), mimes = new WeakMap();
      let lastMimes = null;
      for (const MS of [window.MediaSource, window.ManagedMediaSource, window.WebKitMediaSource]) {
        if (!MS || !MS.prototype.addSourceBuffer || MS.prototype.addSourceBuffer.__lull) continue;
        const add = MS.prototype.addSourceBuffer;
        MS.prototype.addSourceBuffer = function (type) {
          const m = mimes.get(this) || {};
          m[/^audio\//i.test(type) ? 'audio' : 'video'] = type;
          mimes.set(this, m); lastMimes = m;
          return add.apply(this, arguments);
        };
        MS.prototype.addSourceBuffer.__lull = true;
      }
      const createURL = URL.createObjectURL;
      URL.createObjectURL = function (o) {
        const url = createURL.apply(this, arguments);
        if (o && !(o instanceof Blob)) sources.set(url, o);
        return url;
      };
      const mimesOf = v => mimes.get(v.srcObject) || mimes.get(sources.get(v.currentSrc || v.src)) || null;

      // Which key system the page actually picked, not just what's supported.
      let keySystem = null;
      if (navigator.requestMediaKeySystemAccess) {
        const request = navigator.requestMediaKeySystemAccess.bind(navigator);
        navigator.requestMediaKeySystemAccess = (ks, cfg) => request(ks, cfg).then(a => {
          const r = a.createMediaKeys.bind(a);
          a.createMediaKeys = () => r().then(k => { keySystem = a.keySystem; return k; });
          return a;
        });
      }
      if (window.WebKitMediaKeys) {
        const Legacy = window.WebKitMediaKeys;
        window.WebKitMediaKeys = function (ks) { keySystem = ks + ' (legacy)'; return new Legacy(ks); };
        if (Legacy.isTypeSupported) window.WebKitMediaKeys.isTypeSupported = Legacy.isTypeSupported.bind(Legacy);
        window.WebKitMediaKeys.prototype = Legacy.prototype;
      }

      const codecIn = type => { const m = /codecs\s*=\s*"?([^";]+)/i.exec(type || ''); return m ? m[1].trim() : ''; };
      const H264 = { 42: 'Baseline', '4D': 'Main', 58: 'Extended', 64: 'High', '6E': 'High 10', '7A': 'High 4:2:2', F4: 'High 4:4:4' };
      // Names a codec string and, where the string says so, its bit depth and transfer function.
      const describe = c => {
        const f = c.split('.'), tag = f[0].toLowerCase();
        const transfer = t => ({ 16: 'pq', 18: 'hlg' })[+t] || (t ? 'sdr' : null);
        switch (tag) {
          case 'avc1': case 'avc3': {
            const p = (f[1] || '').slice(0, 2).toUpperCase(), lvl = parseInt((f[1] || '').slice(4, 6), 16);
            return { name: 'H.264 ' + (H264[p] || p) + (lvl ? ' ' + (lvl / 10).toFixed(1) : ''), depth: p === '6E' ? 10 : 8 };
          }
          case 'hvc1': case 'hev1': {
            const p = +(f[1] || '').replace(/^[A-C]/i, '');
            return { name: 'HEVC ' + ({ 1: 'Main', 2: 'Main 10', 3: 'Main Still', 4: 'RExt' }[p] || 'profile ' + p), depth: p === 2 ? 10 : 8 };
          }
          case 'dvh1': case 'dvhe': case 'dav1': case 'dva1': case 'dvav':
            return { name: 'Dolby Vision profile ' + +f[1] + (f[2] ? ' level ' + +f[2] : ''), depth: 10, hdr: 'Dolby Vision' };
          case 'vp09': case 'vp9':
            return { name: 'VP9 profile ' + +(f[1] || 0), depth: +f[3] || 8, transfer: transfer(f[6]) };
          case 'vp8': return { name: 'VP8', depth: 8 };
          case 'av01':
            return { name: 'AV1 ' + ({ 0: 'Main', 1: 'High', 2: 'Professional' }[+f[1]] || ''), depth: +f[3] || 8, transfer: transfer(f[7]) };
          case 'mp4a': return { name: ({ '40.2': 'AAC-LC', '40.5': 'HE-AAC', '40.29': 'HE-AACv2', '40.34': 'MP3', a5: 'AC-3', a6: 'E-AC-3' })[f.slice(1).join('.')] || 'AAC' };
          case 'ec-3': return { name: 'E-AC-3 (Dolby Digital Plus)' };
          case 'ac-3': return { name: 'AC-3 (Dolby Digital)' };
          case 'ac-4': return { name: 'AC-4' };
          case 'opus': case 'flac': case 'alac': case 'vorbis': return { name: tag.toUpperCase() };
          default: return { name: c };
        }
      };
      const hdrOf = (d, transfer, meta) => {
        if (d.hdr) return d.hdr;
        if (meta === 'smpteSt2094-10') return 'Dolby Vision';
        if (meta === 'smpteSt2094-40') return 'HDR10+';
        const t = transfer || d.transfer;
        if (t === 'pq') return meta === 'smpteSt2086' ? 'HDR10' : 'HDR10 (PQ)';
        if (t === 'hlg') return 'HLG';
        if (t) return 'SDR';
        return d.depth >= 10 ? '10-bit, transfer unknown' : 'SDR';
      };
      // WebKit's track configuration covers native HLS too; the MSE codec string is the fallback.
      const track = list => { if (!list) return null; for (let i = 0; i < list.length; i++) if (list[i].selected || list[i].enabled) return list[i]; return list[0] || null; };
      const videoDetails = v => {
        const conf = (track(v.videoTracks) || {}).configuration, aconf = (track(v.audioTracks) || {}).configuration;
        const m = mimesOf(v) || (v.currentSrc.startsWith('blob:') ? lastMimes : null);
        const vc = (conf && conf.codec) || codecIn(m && m.video), ac = (aconf && aconf.codec) || codecIn(m && m.audio);
        const out = {};
        if (vc) {
          const d = describe(vc), cs = conf && conf.colorSpace;
          out.codec = d.name + (d.depth ? ' · ' + d.depth + '-bit' : '') + ' (' + vc + ')'
            + (conf && conf.bitrate ? ' · ' + (conf.bitrate / 1e6).toFixed(1) + ' Mb/s' : '');
          out.HDR = hdrOf(d, cs && cs.transfer, conf && conf.hdrMetadataType)
            + (cs && cs.primaries ? ' · ' + cs.primaries + '/' + cs.transfer : '');
        } else {
          out.codec = v.currentSrc.startsWith('blob:') ? 'unknown (MSE)' : 'unknown (native' + (/m3u8/.test(v.currentSrc) ? ' HLS' : '') + ')';
        }
        if (ac) {
          const d = describe(ac);
          out.audio = d.name + ' (' + ac + ')'
            + (aconf && aconf.numberOfChannels ? ' · ' + aconf.numberOfChannels + 'ch' : '')
            + (aconf && aconf.sampleRate ? ' · ' + aconf.sampleRate / 1000 + ' kHz' : '');
        }
        if (v.mediaKeys || v.webkitKeys) out.DRM = keySystem || 'yes';
        return out;
      };

      const hdrDisplay = matchMedia('(dynamic-range: high)'), hdrVideo = matchMedia('(video-dynamic-range: high)');
      const display = () => post('display', (hdrDisplay.matches ? 'HDR' : 'SDR') + (hdrVideo.matches !== hdrDisplay.matches ? ' (video ' + (hdrVideo.matches ? 'HDR' : 'SDR') + ')' : '')
        + ' · ' + screen.width + '×' + screen.height + ' @' + devicePixelRatio + 'x');
      display();
      hdrDisplay.addEventListener && hdrDisplay.addEventListener('change', display);

      const last = {};
      let frames = null;
      const set = (k, v) => { if (last[k] !== v) { last[k] = v; post(k, v); } };
      setInterval(() => {
        const vids = [...document.querySelectorAll('video')];
        if (!vids.length) { frames = null; for (const k of ['codec', 'audio', 'HDR', 'DRM']) if (last[k]) set(k, '—'); return set('video', 'none'); }
        const v = vids.sort((a, b) => b.videoWidth * b.videoHeight - a.videoWidth * a.videoHeight)[0];
        const q = v.getVideoPlaybackQuality ? v.getVideoPlaybackQuality() : null;
        // Frames actually shown over the last second, while playing.
        let fps = '';
        if (q) {
          if (frames && frames.v === v && !v.paused) fps = ' · ' + Math.round((q.totalVideoFrames - frames.n) / ((performance.now() - frames.t) / 1000)) + ' fps';
          frames = { v, n: q.totalVideoFrames, t: performance.now() };
        }
        let ahead = 0;
        for (let i = 0; i < v.buffered.length; i++) if (v.buffered.start(i) <= v.currentTime && v.currentTime <= v.buffered.end(i)) ahead = v.buffered.end(i) - v.currentTime;
        set('video', (v.paused ? 'paused ' : 'playing ') + v.videoWidth + '×' + v.videoHeight + fps
          + (q ? ' · dropped ' + q.droppedVideoFrames + '/' + q.totalVideoFrames : '')
          + ' · buffer ' + ahead.toFixed(1) + 's'
          + (v.playbackRate !== 1 ? ' · ' + v.playbackRate + '×' : ''));
        const d = videoDetails(v);
        for (const k of ['codec', 'audio', 'HDR', 'DRM']) set(k, d[k] || (last[k] ? '—' : undefined));
      }, 1000);
    })();
    """#
}
