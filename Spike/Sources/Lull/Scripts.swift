enum Scripts {
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

    /// Minimal spatial navigation for mouse-first sites: arrows move a focus ring between clickable
    /// elements, Enter clicks. Stays out of the way while a large video is playing so the player
    /// keeps its own arrow/Enter handling.
    static let spatialNav = #"""
    (() => {
      if (window.top !== window || window.__lullNav) return;
      window.__lullNav = true;

      const addStyle = () => {
        const css = document.createElement('style');
        css.textContent = '.lull-focus{outline:4px solid #fff!important;outline-offset:2px!important;'
          + 'box-shadow:0 0 0 8px rgba(0,0,0,.55)!important;border-radius:6px}';
        (document.head || document.documentElement).appendChild(css);
      };
      document.readyState === 'loading' ? addEventListener('DOMContentLoaded', addStyle) : addStyle();

      const SEL = 'a[href],button,input,select,textarea,[role="button"],[role="link"],[role="tab"],'
        + '[role="menuitem"],[role="option"],[tabindex]:not([tabindex="-1"])';
      let cur = null;

      const usable = el => {
        const r = el.getBoundingClientRect();
        if (r.width < 6 || r.height < 6) return false;
        if (r.bottom < -innerHeight || r.top > innerHeight * 2 || r.right < 0 || r.left > innerWidth) return false;
        if (el.disabled || el.closest('[aria-hidden="true"]')) return false;
        const s = getComputedStyle(el);
        return s.visibility !== 'hidden' && s.display !== 'none' && s.pointerEvents !== 'none';
      };
      // Outermost clickable only, so a card and the button inside it don't compete.
      const candidates = () => {
        const all = [...document.querySelectorAll(SEL)].filter(usable);
        const set = new Set(all);
        return all.filter(el => { for (let p = el.parentElement; p; p = p.parentElement) if (set.has(p)) return false; return true; });
      };
      const center = r => ({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
      const isField = el => el.isContentEditable || el.tagName === 'TEXTAREA'
        || (el.tagName === 'INPUT' && ['text', 'search', 'email', 'url', 'tel', 'password', 'number'].includes(el.type));

      const setCur = el => {
        if (cur) cur.classList.remove('lull-focus');
        cur = el;
        if (!el) return;
        el.classList.add('lull-focus');
        // Text fields only take focus when selected, since focusing one brings up the keyboard.
        if (!isField(el)) el.focus({ preventScroll: true });
        el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' });
      };

      const move = dir => {
        const els = candidates();
        if (!cur || !document.contains(cur) || !els.includes(cur)) {
          const onScreen = els.filter(e => { const r = e.getBoundingClientRect(); return r.top >= 0 && r.top < innerHeight; });
          onScreen.sort((a, b) => { const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect(); return (ra.top - rb.top) || (ra.left - rb.left); });
          return setCur(onScreen[0] || els[0]);
        }
        const a = cur.getBoundingClientRect(), ca = center(a);
        const horiz = dir === 'left' || dir === 'right';
        let best = null, bestScore = Infinity;
        for (const el of els) {
          if (el === cur) continue;
          const b = el.getBoundingClientRect(), cb = center(b);
          let main, overlap;
          if (horiz) {
            if (dir === 'right' ? cb.x <= ca.x : cb.x >= ca.x) continue;
            main = dir === 'right' ? b.left - a.right : a.left - b.right;
            overlap = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
          } else {
            if (dir === 'down' ? cb.y <= ca.y : cb.y >= ca.y) continue;
            main = dir === 'down' ? b.top - a.bottom : a.top - b.bottom;
            overlap = Math.min(a.right, b.right) - Math.max(a.left, b.left);
          }
          const cross = overlap > 0 ? 0 : (horiz ? Math.abs(cb.y - ca.y) : Math.abs(cb.x - ca.x));
          const drift = horiz ? 0 : Math.abs(cb.x - ca.x) * 0.1;
          const score = Math.max(main, 0) + cross * 4 + drift;
          if (score < bestScore) { bestScore = score; best = el; }
        }
        if (best) setCur(best);
        else if (!horiz) scrollBy({ top: (dir === 'down' ? 1 : -1) * innerHeight * 0.6, behavior: 'smooth' });
      };

      const playerActive = () => [...document.querySelectorAll('video')]
        .some(v => !v.paused && v.getBoundingClientRect().width > innerWidth * 0.7);
      const typing = () => {
        const a = document.activeElement;
        return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.isContentEditable);
      };
      const DIRS = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' };

      addEventListener('keydown', e => {
        if (playerActive()) { if (cur) setCur(null); return; }
        if (DIRS[e.key]) {
          if (typing() && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) return;
          e.preventDefault(); e.stopImmediatePropagation();
          move(DIRS[e.key]);
        } else if (e.key === 'Enter' && cur && document.contains(cur) && !typing()) {
          e.preventDefault(); e.stopImmediatePropagation();
          if (isField(cur)) cur.focus({ preventScroll: true });
          cur.click();
        }
      }, true);
    })();
    """#

    /// Tells the app which text field has focus and what it's for, so the on-screen keyboard can
    /// show and adapt, and exposes `__lullKB` for the keyboard to edit it.
    static let keyboard = #"""
    (() => {
      if (window.top !== window || window.__lullKB) return;
      const post = m => { try { webkit.messageHandlers.lullKeyboard.postMessage(m); } catch (_) {} };
      const TYPES = ['text', 'search', 'email', 'url', 'tel', 'password', 'number'];
      const editable = el => {
        if (!el || !el.getAttribute || el.disabled || el.readOnly) return false;
        if ((el.getAttribute('inputmode') || '').toLowerCase() === 'none') return false;
        if (el.tagName === 'INPUT') return TYPES.includes(el.type);
        return el.tagName === 'TEXTAREA' || el.isContentEditable;
      };
      const active = () => {
        let a = document.activeElement;
        while (a && a.shadowRoot && a.shadowRoot.activeElement) a = a.shadowRoot.activeElement;
        return a;
      };
      const shown = el => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden';
      };
      const clean = s => (s || '').replace(/\s+/g, ' ').trim().slice(0, 80);
      const valueOf = el => {
        const v = (el.isContentEditable ? el.innerText : el.value) || '';
        return v.length > 2000 ? v.slice(-2000) : v;
      };

      const labelOf = el => {
        const aria = clean(el.getAttribute('aria-label'));
        if (aria) return aria;
        const by = (el.getAttribute('aria-labelledby') || '').split(/\s+/)
          .map(id => id && document.getElementById(id)).filter(Boolean);
        const byText = clean(by.map(n => n.textContent).join(' '));
        if (byText) return byText;
        const label = (el.labels && el.labels[0]) || el.closest('label');
        return clean(label && label.textContent) || clean(el.getAttribute('title'));
      };

      const fieldsIn = root => [...root.querySelectorAll('input, textarea, [contenteditable=""], [contenteditable="true"]')]
        .filter(f => editable(f) && shown(f));
      // The form, or else the nearest ancestor holding other fields: many sign-in pages have no <form>.
      const scopeOf = el => {
        if (el.form) return el.form;
        let p = el.parentElement;
        for (let i = 0; p && i < 6; i++, p = p.parentElement) if (fieldsIn(p).length > 1) return p;
        return null;
      };
      const following = (el, scope) => scope
        ? fieldsIn(scope).filter(f => f !== el && (el.compareDocumentPosition(f) & Node.DOCUMENT_POSITION_FOLLOWING))
        : [];
      const searchy = (el, label) => {
        if (el.type === 'search' || el.getAttribute('role') === 'searchbox' || el.closest('[role="search"], search')) return true;
        if (el.name === 'q' || el.name === 'query') return true;
        if (el.form && /search|query|find/i.test(el.form.getAttribute('action') || '')) return true;
        return /search|keres|such|recherch|busca|cerca|zoek|szuk/i
          .test([label, el.getAttribute('placeholder'), el.name, el.id].join(' '));
      };

      const info = el => {
        const scope = scopeOf(el), label = labelOf(el);
        const attr = n => el.getAttribute(n) || '';
        return {
          type: el.tagName === 'INPUT' ? el.type : el.tagName === 'TEXTAREA' ? 'textarea' : 'contenteditable',
          inputMode: attr('inputmode'), autocomplete: attr('autocomplete').toLowerCase(),
          enterKeyHint: attr('enterkeyhint'), autocapitalize: attr('autocapitalize'), pattern: attr('pattern'),
          label, placeholder: clean(attr('placeholder')), name: clean(attr('name') || el.id),
          maxLength: el.maxLength > 0 ? el.maxLength : 0,
          search: searchy(el, label),
          hasNext: following(el, scope).length > 0,
          inForm: !!scope,
          login: !!(scope && scope.querySelector('input[type="password"]')),
          options: el.list ? [...el.list.options].map(o => clean(o.value)).filter(Boolean).slice(0, 20) : [],
        };
      };

      let cur = null, token = 0, last = null;
      const report = e => {
        if (!cur) return;
        const v = valueOf(cur);
        if (e === 'value' && v === last) return;
        last = v;
        post(e === 'focus' ? { e, id: token, field: info(cur), value: v } : { e, id: token, value: v });
      };

      addEventListener('focusin', () => {
        const el = active();
        if (!editable(el)) return;
        if (el !== cur) {
          cur = el; token++;
          // Selected by remote rather than clicked into: type at the end, not the start.
          try { if (el.value && el.selectionStart === 0 && el.selectionEnd === 0) el.setSelectionRange(el.value.length, el.value.length); } catch (_) {}
        }
        report('focus');
      }, true);

      // Focus went somewhere that isn't a field, or the field left the page. When the window loses
      // focus (e.g. to the remote simulator) the element stays active, so the keyboard stays.
      const check = () => {
        if (!cur || (active() === cur && cur.isConnected)) return;
        post({ e: 'blur', id: token });
        cur = null; last = null;
      };
      addEventListener('focusout', () => setTimeout(check, 0), true);
      addEventListener('input', () => setTimeout(() => report('value'), 0), true);
      // Pages also change values without input events (clearing after submit, formatting).
      setInterval(() => { check(); report('value'); }, 400);

      const target = () => {
        if (!cur || !cur.isConnected) return null;
        if (active() !== cur) cur.focus({ preventScroll: true });
        return cur;
      };
      const selection = el => { try { return [el.selectionStart, el.selectionEnd]; } catch (_) { return [null, null]; } };
      const setValue = (el, v, caret) => {
        const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
        try { el.setSelectionRange(caret, caret); } catch (_) {}
        el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
      };
      // execCommand goes through the editor like real typing, so frameworks see ordinary input
      // events. It can refuse (e.g. while the window isn't key); then the value is set directly.
      const edit = (command, arg, fallback) => {
        const el = target();
        if (!el) return null;
        const before = valueOf(el);
        let ok = false;
        try { ok = document.execCommand(command, false, arg); } catch (_) {}
        if ((!ok || valueOf(el) === before) && !el.isContentEditable) fallback(el);
        return valueOf(el);
      };
      const range = el => { let [s, e] = selection(el); if (s == null) s = e = el.value.length; return [s, e]; };

      const KB = {
        insert: t => edit('insertText', t, el => {
          const v = el.value, [s, e] = range(el);
          const add = el.maxLength > 0 ? t.slice(0, Math.max(0, el.maxLength - (v.length - (e - s)))) : t;
          if (add) setValue(el, v.slice(0, s) + add + v.slice(e), s + add.length);
        }),
        del: () => edit('delete', null, el => {
          const v = el.value, [s, e] = range(el);
          if (s !== e) return setValue(el, v.slice(0, s) + v.slice(e), s);
          if (s === 0) return;
          const n = s > 1 && /[\uDC00-\uDFFF]/.test(v[s - 1]) ? 2 : 1;
          setValue(el, v.slice(0, s - n) + v.slice(s), s - n);
        }),
        clear: () => {
          const el = target();
          if (!el) return null;
          try { el.select ? el.select() : document.execCommand('selectAll'); } catch (_) {}
          return edit('delete', null, el => { if (el.value) setValue(el, '', 0); });
        },
        replace: t => { KB.clear(); return KB.insert(t); },
        next: () => {
          const f = cur && following(cur, scopeOf(cur))[0];
          if (!f) return false;
          f.focus();
          return true;
        },
        dismiss: () => {
          const el = cur;
          cur = null; last = null;
          if (el) el.blur();
          return true;
        },
        // After Return: close the field unless the page moved focus on by itself.
        settle: t => { if (t === token && cur && active() === cur) KB.dismiss(); return true; },
      };
      window.__lullKB = KB;
    })();
    """#

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
