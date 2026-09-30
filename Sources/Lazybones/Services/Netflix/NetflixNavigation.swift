extension Netflix {
    /// Remote navigation for netflix.com, modelled on the TV app:
    ///
    /// - Arrows move between tiles by position, and remember their column, so Down then Up comes
    ///   back to the tile you left even when the row between has differently sized tiles.
    /// - A tile that's only peeking in at the edge of a row pages the slider first, then takes focus.
    /// - The focused tile is raised and ringed, and the page scrolls to keep its row in view.
    /// - Select opens the details panel and focus goes to its Play button. While it's open, arrows stay
    ///   inside it; Back closes it, and focus returns to the tile.
    /// - Back with the page scrolled down goes to the top before it goes Home (see `Scripts.pageBack`).
    /// - Header menus (profile, notifications) open on hover, so Select on one hovers it and a second
    ///   Select clicks.
    /// - On the player, Left/Right seek as Netflix does. Up/Down never change the volume (that's the
    ///   remote's job): they wake the controls and move focus into them, where arrows move between
    ///   controls and Select presses one. Back drops focus back to the video.
    ///
    /// It relies on Netflix's markup: `.title-card`, `.slider-item`, `.handleNext`, `data-uia`
    /// attributes. Anything it doesn't recognise still gets the generic geometric behaviour.
    static let navigation = #"""
    (() => {
      if (window.top !== window || window.__lazybonesNetflixNav) return;
      window.__lazybonesNetflixNav = true;

      const addStyle = () => {
        const css = document.createElement('style');
        css.textContent = '.lazybones-focus{outline:4px solid #fff!important;outline-offset:3px!important;'
          + 'border-radius:6px;box-shadow:0 10px 30px rgba(0,0,0,.65)!important}'
          + '.lazybones-card{transform:scale(1.06);transition:transform .15s ease-out;z-index:5}';
        (document.head || document.documentElement).appendChild(css);
      };
      document.readyState === 'loading' ? addEventListener('DOMContentLoaded', addStyle) : addStyle();

      const SEL = 'a[href],button,input,select,textarea,[role="button"],[role="link"],[role="tab"],'
        + '[role="menuitem"],[role="option"],[tabindex]:not([tabindex="-1"])';
      const CARD = '.title-card, .slider-item';
      const HEADER = '.pinning-header, header, [role="banner"]';
      const BILLBOARD = '.billboard-row, .billboard, [data-uia^="billboard"]';
      const MODAL = '[data-uia*="preview-modal"], .previewModal--container, [role="dialog"], [aria-modal="true"]';
      const ROW = '.lolomoRow, [data-list-context], .rowContainer, .slider';
      const POPUP = '[aria-haspopup], .account-menu-item, .notifications';
      const PLAY = '[data-uia="play-button"]';
      const PLAYER_BUTTONS = '[data-uia="player-skip-intro"], [data-uia="next-episode-seamless-button"],'
        + '[data-uia="next-episode-seamless-button-draining"]';
      const DIRS = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' };
      const SLIDE_MS = 750;

      let cur = null, curKey = null, col = 0, ring = null;
      let modal = null, beforeModal = null, hovered = null, busy = false;

      const onPlayer = () => location.pathname.startsWith('/watch');
      const rect = el => el.getBoundingClientRect();
      const center = r => ({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
      const isField = el => el.isContentEditable || el.tagName === 'TEXTAREA'
        || (el.tagName === 'INPUT' && ['text', 'search', 'email', 'url', 'tel', 'password', 'number'].includes(el.type));
      const typing = () => {
        const a = document.activeElement;
        return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.isContentEditable);
      };
      // The title's id from a tile's link, to find the same tile again after a slide or a re-render.
      const keyOf = el => {
        const a = el.matches('a[href]') ? el : el.querySelector('a[href]');
        const m = a && a.href.match(/\/(?:watch|title)\/(\d+)/);
        return m ? m[1] : null;
      };

      const usable = el => {
        const r = rect(el);
        if (r.width < 6 || r.height < 6) return false;
        if (r.bottom < -innerHeight || r.top > innerHeight * 2 || r.right < 0 || r.left > innerWidth) return false;
        if (el.disabled || el.closest('[aria-hidden="true"], [inert], .handle')) return false;
        const s = getComputedStyle(el);
        return s.visibility !== 'hidden' && s.display !== 'none' && s.pointerEvents !== 'none' && s.opacity !== '0';
      };
      // Outermost clickable only, so a tile and the link inside it don't compete. Inside the details
      // panel while it's open: the page behind it isn't reachable.
      const candidates = () => {
        const all = [...(modal || document).querySelectorAll(SEL)].filter(usable);
        const set = new Set(all);
        return all.filter(el => { for (let p = el.parentElement; p; p = p.parentElement) if (set.has(p)) return false; return true; });
      };

      const fire = (el, types) => types.forEach(t =>
        el.dispatchEvent(new MouseEvent(t, { bubbles: t !== 'mouseenter' && t !== 'mouseleave', view: window })));
      const unhover = () => {
        if (hovered) fire(hovered, ['pointerout', 'mouseout', 'mouseleave']);
        hovered = null;
      };

      const reveal = el => {
        if (onPlayer()) return;
        if (modal) return el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        if (el.closest(HEADER)) return;
        // The billboard stays whole; a row goes just above the middle, with the next one peeking in.
        if (el.closest(BILLBOARD)) return scrollTo({ top: 0, behavior: 'smooth' });
        const r = rect(el);
        scrollTo({ top: Math.max(0, scrollY + r.top + r.height / 2 - innerHeight * 0.45), behavior: 'smooth' });
      };

      const setCur = (el, { keepCol = false, quiet = false } = {}) => {
        if (ring) ring.classList.remove('lazybones-focus', 'lazybones-card');
        cur = el; ring = null;
        if (hovered && !(el && hovered.contains(el))) unhover();
        if (!el) { curKey = null; return; }
        ring = el.closest(CARD) || el;
        ring.classList.add('lazybones-focus');
        if (ring !== el) ring.classList.add('lazybones-card');
        curKey = keyOf(el);
        if (!keepCol) col = center(rect(el)).x;
        // Text fields only take focus when selected, since focusing one brings up the keyboard.
        if (!isField(el)) el.focus({ preventScroll: true });
        if (!quiet) reveal(el);
      };

      // The focused element if it's still on the page, found again by title if the page re-rendered it.
      const resolve = els => {
        if (cur && cur.isConnected) return els.includes(cur) ? cur : null;
        return (curKey && els.find(e => keyOf(e) === curKey)) || null;
      };

      const firstFocus = els => {
        if (modal) return modal.querySelector(PLAY) || els[0];
        const onScreen = els.filter(e => { const r = rect(e); return r.top >= 0 && r.bottom <= innerHeight && r.left >= 0; });
        const pool = onScreen.length ? onScreen : els;
        const play = pool.find(e => e.matches(PLAY));
        if (play) return play;
        // Content before chrome, like the TV app: the header is one Up away.
        const body = pool.filter(e => !e.closest(HEADER));
        return (body.length ? body : pool).sort((a, b) => {
          const ra = rect(a), rb = rect(b);
          return (ra.top - rb.top) || (ra.left - rb.left);
        })[0];
      };

      const sameRow = (a, b) => Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 0.4 * Math.min(a.height, b.height);
      const whole = r => r.left >= -2 && r.right <= innerWidth + 2;

      // Tiles beyond the row's last full one are only peeking in; the slider pages before they're
      // selected. Resolves the tile again afterwards, since the slider re-renders its items.
      const page = (dir, target) => {
        const key = keyOf(target), want = dir === 'right' ? '.handleNext' : '.handlePrev';
        // Sliders keep their handles at different depths, so look outward from the tile.
        let row = target.closest(ROW), handle = null;
        for (; row && !handle; row = row.parentElement && row.parentElement.closest(ROW)) handle = row.querySelector(want);
        if (!handle || !key || rect(handle).width === 0) return false;
        row = handle.closest(ROW);
        busy = true;
        handle.click();
        setTimeout(() => {
          busy = false;
          const again = [...document.querySelectorAll(SEL)].find(e => keyOf(e) === key && usable(e));
          if (again) setCur(again);
        }, SLIDE_MS);
        return true;
      };

      const horizontal = (dir, els, from) => {
        const a = rect(from), ca = center(a), sign = dir === 'right' ? 1 : -1;
        let best = null, bestD = Infinity;
        for (const el of els) {
          if (el === from) continue;
          const b = rect(el), d = (center(b).x - ca.x) * sign;
          if (d <= 0 || !sameRow(a, b)) continue;
          if (d < bestD) { bestD = d; best = el; }
        }
        if (!best) return;
        if (!whole(rect(best)) && page(dir, best)) return;
        setCur(best);
      };

      const inHeader = el => !!el.closest(HEADER);

      // The tile in the nearest row of `pool` in that direction, closest to the remembered column.
      const nearestRow = (pool, a, dir, anywhere = false) => {
        const ca = center(a), sign = dir === 'down' ? 1 : -1;
        const rows = pool.map(el => ({ el, b: rect(el) }))
          .filter(o => anywhere || ((center(o.b).y - ca.y) * sign > 0 && !sameRow(a, o.b)))
          .map(o => ({ ...o, dy: Math.abs(center(o.b).y - ca.y) }));
        if (!rows.length) return null;
        const near = Math.min(...rows.map(o => o.dy));
        const band = rows.filter(o => o.dy - near < Math.max(24, Math.min(a.height, o.b.height) * 0.5));
        const fit = band.filter(o => whole(o.b));
        return (fit.length ? fit : band)
          .sort((p, q) => Math.abs(center(p.b).x - col) - Math.abs(center(q.b).x - col))[0].el;
      };

      const vertical = (dir, els, from, retried) => {
        const a = rect(from), pool = els.filter(el => el !== from);
        const header = pool.filter(inHeader), body = pool.filter(el => !inHeader(el));
        // The header is fixed, so it's above everything however far the page has scrolled: Up reaches
        // it only once there's no row left above (wherever a scroll in flight has left them), and Down
        // from it goes into the page.
        const pick = inHeader(from) ? nearestRow(dir === 'down' ? body : header, a, dir)
          : nearestRow(body, a, dir) || (dir === 'up' ? nearestRow(header, a, dir, true) : null);
        if (pick) return setCur(pick, { keepCol: true });
        // Nothing further: more rows load as the page scrolls, so try once more after scrolling.
        if (modal) return;
        if (dir === 'down' && !retried) {
          scrollBy({ top: innerHeight * 0.6, behavior: 'smooth' });
          setTimeout(() => { const e = candidates(), c = resolve(e); if (c) vertical(dir, e, c, true); }, 450);
        } else if (dir === 'up' && scrollY > 0) {
          scrollTo({ top: 0, behavior: 'smooth' });
        }
      };

      const move = dir => {
        const els = candidates();
        const from = resolve(els);
        if (!from) return setCur(firstFocus(els));
        if (dir === 'left' || dir === 'right') { if (!busy) horizontal(dir, els, from); }
        else vertical(dir, els, from);
      };

      const select = () => {
        const els = candidates(), c = resolve(els);
        if (!c) return false;
        // Menus in the header open on hover: hover first, click on the second press.
        const popup = c.closest(POPUP);
        if (popup && popup !== hovered && !isField(c)) {
          hovered = popup;
          fire(popup, ['pointerover', 'mouseover', 'mouseenter']);
          return true;
        }
        if (isField(c)) c.focus({ preventScroll: true });
        c.click();
        return true;
      };

      // --- The player ---------------------------------------------------------------------------
      // Netflix fades its controls out a few seconds after the last mouse move, so every remote press
      // moves the mouse a pixel. Controls are found by being visible buttons, not by class names.
      let nudge = 0;
      const wake = () => {
        const target = document.elementFromPoint(innerWidth / 2, innerHeight / 2) || document.body;
        nudge ^= 1;
        const init = { bubbles: true, view: window, clientX: innerWidth / 2 + nudge, clientY: innerHeight / 2 };
        ['pointermove', 'mousemove'].forEach(t => target.dispatchEvent(new MouseEvent(t, init)));
      };
      const shown = el => {
        for (let p = el; p; p = p.parentElement) if (getComputedStyle(p).opacity === '0') return false;
        return true;
      };
      const controls = () => [...document.querySelectorAll('button, [role="button"], a[href]')]
        .filter(el => usable(el) && shown(el) && rect(el).width < innerWidth * 0.6);
      const focusControls = () => {
        const els = controls();
        if (!els.length) return;
        const bottom = Math.max(...els.map(e => rect(e).bottom));
        setCur(els.find(e => (e.dataset.uia || '').startsWith('control-play-pause'))
          || els.filter(e => rect(e).bottom > bottom - 20).sort((a, b) => rect(a).left - rect(b).left)[0]);
      };
      // Pressing a control often swaps its element (play becomes pause), so focus goes to whatever
      // control is now where it was.
      const refocusNear = pt => setTimeout(() => {
        if (cur && cur.isConnected) return;
        const best = controls().map(el => ({ el, d: Math.hypot(center(rect(el)).x - pt.x, center(rect(el)).y - pt.y) }))
          .sort((a, b) => a.d - b.d)[0];
        if (best && best.d < 80) setCur(best.el, { quiet: true });
      }, 200);

      const playerKey = e => {
        if (typing()) return;
        const dir = DIRS[e.key], swallow = () => { e.preventDefault(); e.stopImmediatePropagation(); };
        if (!cur) {
          if (dir === 'up' || dir === 'down') { swallow(); wake(); setTimeout(focusControls, 150); return; }
          if (e.key !== 'Enter') return;   // Left and Right seek, Netflix's own way
          const skip = [...document.querySelectorAll(PLAYER_BUTTONS)].find(usable);
          if (skip) { swallow(); skip.click(); }
          return;
        }
        if (!dir && e.key !== 'Enter') return;
        swallow();
        wake();
        if (dir) return stepControls(dir);
        const pt = center(rect(cur));
        cur.click();
        refocusNear(pt);
      };
      const stepControls = dir => {
        const els = controls();
        if (!els.includes(cur)) return setCur(null);
        if (dir === 'left' || dir === 'right') return horizontal(dir, els, cur);
        const pick = nearestRow(els.filter(el => el !== cur), rect(cur), dir);
        // Down from the bottom row gives the video back.
        if (pick) setCur(pick, { keepCol: true });
        else if (dir === 'down') setCur(null);
      };

      const modalRoot = () => [...document.querySelectorAll(MODAL)].find(m => rect(m).width > 200 && rect(m).height > 100) || null;
      const closeModal = () => {
        const x = modal && modal.querySelector('[data-uia*="closebtn"], [data-uia*="close-button"], [aria-label="Close" i]');
        if (!x) return false;
        x.click();
        return true;
      };

      // Focus follows the details panel: into it when it opens, back to the tile when it closes.
      // Watching for it is simpler than knowing every way Netflix opens and closes it.
      setInterval(() => {
        if (onPlayer()) { if (cur && cur.isConnected && !shown(cur)) setCur(null); modal = null; return; }
        const m = modalRoot();
        if (m === modal) return;
        if (m && !modal) beforeModal = cur;
        modal = m;
        if (m) {
          // The panel animates in from its tile, so pick by what it is, not where it is (yet).
          setCur(m.querySelector(PLAY) || firstFocus(candidates()), { quiet: true });
        } else {
          const back = beforeModal && beforeModal.isConnected ? beforeModal : null;
          beforeModal = null;
          setCur(back, { quiet: true });
        }
      }, 200);

      // Back: closes what Select opened, then returns to the top of the page. False lets Lazybones go to
      // the previous page, or Home.
      window.__lazybonesBack = () => {
        if (onPlayer()) {
          if (!cur) return false;
          setCur(null);
          return true;
        }
        if (hovered) { unhover(); return true; }
        if (typing()) { document.activeElement.blur(); return true; }
        if (modal) return closeModal();
        if (scrollY > 50) {
          scrollTo({ top: 0, behavior: 'smooth' });
          setCur(null);
          return true;
        }
        return false;
      };

      addEventListener('keydown', e => {
        if (e.metaKey || e.ctrlKey || e.altKey) return;
        if (onPlayer()) return playerKey(e);
        const dir = DIRS[e.key];
        if (dir) {
          if (typing() && (dir === 'left' || dir === 'right')) return;
          e.preventDefault(); e.stopImmediatePropagation();
          move(dir);
        } else if (e.key === 'Enter' && !typing()) {
          if (select()) { e.preventDefault(); e.stopImmediatePropagation(); }
        }
      }, true);
    })();
    """#
}
