extension Netflix {
    /// Remote navigation for netflix.com, modelled on the TV app:
    ///
    /// - Arrows move between tiles by position, and remember their column, so Down then Up comes
    ///   back to the tile you left even when the row between has differently sized tiles.
    /// - A tile that's only peeking in at the edge of a row pages the slider first, and focus rides
    ///   along with the slide. Presses made during it run once it's over.
    /// - The focused tile is raised and ringed, and the page scrolls to keep its row in view.
    /// - Up from the top of the page lands on the current tab in the header, like the TV app's menu.
    /// - Select opens the details panel and focus goes to its Play button. While it's open, arrows stay
    ///   inside it, skipping the cast and genre links; Back closes it, and focus returns to the tile.
    /// - Menus (profile, notifications, the season picker) work the same way: arrows stay inside, Back
    ///   closes them, and focus returns to their button.
    /// - Back with the page scrolled down goes to the top before it goes Home (see `Scripts.pageBack`).
    /// - On the player, Left/Right seek as Netflix does. Up/Down never change the volume (that's the
    ///   remote's job): they wake the controls and move focus into them, where arrows move between
    ///   controls and Select presses one. Presses made while the controls come up wait for them.
    ///   Back drops focus back to the video.
    /// - The audio & subtitles, speed and episodes panels take focus on their current choice, and Back
    ///   closes them. The episodes list moves its own highlight, so arrows go straight to it.
    ///
    /// It relies on Netflix's markup, mostly `data-uia` attributes (`standard-card`,
    /// `carousel-row-section-…`, `carousel-hawkins-right-button`, `modal-motion-container-…`), with
    /// the classes of its previous design (`.title-card`, `.handleNext`) kept as a fallback. Anything
    /// it doesn't recognise still gets the generic geometric behaviour.
    static let navigation = #"""
    (() => {
      if (window.top !== window || window.__lazybonesNetflixNav) return;
      window.__lazybonesNetflixNav = true;

      const addStyle = () => {
        const css = document.createElement('style');
        css.textContent = '.lazybones-focus{outline:4px solid #fff!important;outline-offset:3px!important;'
          + 'border-radius:6px;box-shadow:0 10px 30px rgba(0,0,0,.65)!important}'
          + '.lazybones-card{outline-offset:-4px!important;transform:scale(1.04);transition:transform .15s ease-out;z-index:5}';
        (document.head || document.documentElement).appendChild(css);
      };
      document.readyState === 'loading' ? addEventListener('DOMContentLoaded', addStyle) : addStyle();

      // Netflix's current markup first (data-uia), then the classes it used before, which still turn up
      // in some of its A/B tests.
      const SEL = 'a[href],button,input,select,textarea,[role="button"],[role="link"],[role="tab"],'
        + '[role="menuitem"],[role="menuitemradio"],[role="option"],[tabindex]:not([tabindex="-1"])';
      const CARD = '[data-uia="standard-card"], [data-uia="progress-card"], .title-card, .slider-item';
      const HEADER = '[data-uia="navigation"], .pinning-header, header, [role="banner"]';
      const BILLBOARD = '[data-uia="billboard"], .billboard-row, .billboard';
      const MODAL = '[data-uia^="modal-motion-container"], .previewModal--container, [role="dialog"], [aria-modal="true"]';
      const MENU = '[role="menu"], [role="listbox"]';
      const ROW = 'section[data-uia^="carousel-row"], [data-uia="carousel-scroller"], .lolomoRow, [data-list-context], .rowContainer, .slider';
      const NEXT = '[data-uia="carousel-hawkins-right-button"], .handleNext';
      const PREV = '[data-uia="carousel-hawkins-left-button"], .handlePrev';
      const PLAY = '[data-uia="play-button"], [data-uia="play-video-button"]';
      // Never focused, nor anything inside: the logo goes nowhere useful, the slider handles are what Left
      // and Right are for, the remote has its own volume, and the TV app's details page has no cast, genre
      // or rating links to trip over between Play and the episodes.
      const SKIP = '[data-uia="navigation+logo"], [data-uia^="carousel-hawkins"], [data-uia="billboard-controls"], .handle,'
        + '[data-uia="tag-item"], [data-uia="tag-more"], [data-uia="previewModal--detailsMetadata"] a';
      const PLAYER_BUTTONS = '[data-uia="player-skip-intro"], [data-uia="next-episode-seamless-button"],'
        + '[data-uia="next-episode-seamless-button-draining"]';
      const DIRS = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' };

      let cur = null, curKey = null, col = 0, ring = null;
      let modal = null, beforeModal = null, menu = null, beforeMenu = null, busy = false, queued = null;

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
        const m = a && a.href.match(/\/(?:watch|title)\/(\d+)|[?&]jbv=(\d+)/);
        return m ? m[1] || m[2] : null;
      };

      const usable = el => {
        const r = rect(el);
        if (r.width < 6 || r.height < 6) return false;
        if (r.bottom < -innerHeight || r.top > innerHeight * 2 || r.right < 0 || r.left > innerWidth) return false;
        if (el.disabled || el.closest(SKIP) || el.closest('[aria-hidden="true"], [inert]')) return false;
        const s = getComputedStyle(el);
        // Pointer events go off for the whole page while it scrolls, which says nothing about one element.
        const pointer = s.pointerEvents !== 'none' || document.body.style.pointerEvents === 'none';
        return s.visibility !== 'hidden' && s.display !== 'none' && pointer && s.opacity !== '0';
      };
      // Outermost clickable only, so a tile and the link inside it don't compete. Inside an open menu or
      // the details panel, only what's in it: the page behind isn't reachable.
      const candidates = () => {
        const all = [...(menu || modal || document).querySelectorAll(SEL)].filter(usable);
        const set = new Set(all);
        return all.filter(el => { for (let p = el.parentElement; p; p = p.parentElement) if (set.has(p)) return false; return true; });
      };

      const reveal = el => {
        if (onPlayer()) return;
        if (menu) return el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        if (modal) {
          // The top of the panel stays whole while its buttons have focus; episodes and the rest come
          // to the middle of the screen. The page scrolls the panel, not the panel itself.
          const top = scrollY + rect(modal).top - 32;
          if (scrollY + rect(el).top - top < innerHeight * 0.5) return scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
          return el.scrollIntoView({ block: 'center', behavior: 'smooth' });
        }
        if (el.closest(HEADER)) return;
        // The billboard stays whole; a row goes just above the middle, with the next one peeking in.
        if (el.closest(BILLBOARD)) return scrollTo({ top: 0, behavior: 'smooth' });
        const r = rect(el);
        scrollTo({ top: Math.max(0, scrollY + r.top + r.height / 2 - innerHeight * 0.45), behavior: 'smooth' });
      };

      const setCur = (el, { keepCol = false, quiet = false } = {}) => {
        if (ring) ring.classList.remove('lazybones-focus', 'lazybones-card');
        // Letting go lets go of the page's focus too, or a player button keeps Netflix's own highlight.
        if (!el && cur && document.activeElement === cur) cur.blur();
        cur = el; ring = null;
        if (!el) { curKey = null; return; }
        ring = el.closest(CARD) || el;
        ring.classList.add('lazybones-focus');
        if (ring.matches(CARD)) ring.classList.add('lazybones-card');
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
        if (menu) return els.find(e => e === document.activeElement) || els[0];
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

      // Calls `done` once `el` has stopped moving: a slide takes about a second, longer on a busy page.
      const settle = (el, done) => {
        const t0 = performance.now();
        let last = null;
        const tick = () => {
          const x = el.isConnected ? rect(el).left : 0, t = performance.now() - t0;
          if ((t > 200 && last !== null && Math.abs(x - last) < 0.5) || t > 1600) return done();
          last = x;
          requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      };

      // Tiles beyond the row's last full one are only peeking in; the slider pages to them first. Focus
      // moves straight away and rides along with the slide; a press made meanwhile runs once it's over.
      const page = (dir, target) => {
        const want = dir === 'right' ? NEXT : PREV;
        // Sliders keep their handles at different depths, so look outward from the tile.
        let row = target.closest(ROW), handle = null;
        for (; row && !handle; row = row.parentElement && row.parentElement.closest(ROW)) handle = row.querySelector(want);
        if (!handle || rect(handle).width === 0) return false;
        busy = true;
        handle.click();
        setCur(target, { quiet: true });
        settle(target, () => {
          busy = false;
          // Older sliders re-render their items, so find the tile again by title.
          if (!target.isConnected) {
            const again = curKey && [...document.querySelectorAll(SEL)].find(e => keyOf(e) === curKey && usable(e));
            if (again) setCur(again, { quiet: true });
          }
          if (cur) reveal(cur);
          const next = queued;
          queued = null;
          if (next) move(next);
        });
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
        // The header is pinned, so it's above everything however far the page has scrolled: Up reaches
        // it only once there's no row left above (wherever a scroll in flight has left them), and Down
        // from it goes into the page.
        const pick = inHeader(from) ? nearestRow(dir === 'down' ? body : header, a, dir)
          : nearestRow(body, a, dir);
        if (pick) return setCur(pick, { keepCol: true });
        // Into the header, on the current tab like the TV app's menu, whatever column you came from.
        if (dir === 'up' && header.length && !inHeader(from)) {
          return setCur(header.find(e => e.matches('[aria-current="page"]')) || nearestRow(header, a, dir, true));
        }
        // Nothing further: more rows load as the page scrolls, so try once more after scrolling.
        if (modal || menu) return;
        if (dir === 'down' && !retried) {
          scrollBy({ top: innerHeight * 0.6, behavior: 'smooth' });
          setTimeout(() => { const e = candidates(), c = resolve(e); if (c) vertical(dir, e, c, true); }, 450);
        } else if (dir === 'up' && scrollY > 0) {
          scrollTo({ top: 0, behavior: 'smooth' });
        }
      };

      const move = dir => {
        if (busy) { queued = dir; return; }
        const els = candidates();
        const from = resolve(els);
        if (!from) return setCur(firstFocus(els));
        if (dir === 'left' || dir === 'right') horizontal(dir, els, from);
        else vertical(dir, els, from);
      };

      const select = () => {
        const els = candidates(), c = resolve(els);
        if (!c) return false;
        if (isField(c)) c.focus({ preventScroll: true });
        c.click();
        // Search opens a field next to its button: go straight into it, as if it had been selected, once
        // it has faded in.
        if (c.closest(HEADER) && /search/.test(c.dataset.uia || '')) {
          let tries = 0;
          const into = () => {
            const f = [...document.querySelectorAll(HEADER + ' input')].find(usable);
            if (f) { setCur(f); f.focus(); } else if (++tries < 15) setTimeout(into, 100);
          };
          setTimeout(into, 100);
        }
        return true;
      };

      // --- The player ---------------------------------------------------------------------------
      // Netflix takes its controls off the page a few seconds after the last mouse move, so every remote
      // press moves the mouse. It only listens for a real PointerEvent from a mouse, on whatever is under
      // it, and ignores one that lands where the last did: two moves a pixel apart make sure one counts,
      // wherever the real mouse was left. Controls are found by being visible buttons, not by class names.
      const wake = () => {
        const target = document.elementFromPoint(innerWidth / 2, innerHeight / 2) || document.body;
        for (const dx of [0, 1]) {
          const init = { bubbles: true, view: window, clientX: innerWidth / 2 + dx, clientY: innerHeight / 2 };
          target.dispatchEvent(new PointerEvent('pointermove', { ...init, pointerType: 'mouse', isPrimary: true }));
          target.dispatchEvent(new MouseEvent('mousemove', init));
        }
      };
      const shown = el => {
        for (let p = el; p; p = p.parentElement) if (getComputedStyle(p).opacity === '0') return false;
        return true;
      };
      const controls = () => [...document.querySelectorAll('button, [role="button"], a[href]')]
        .filter(el => usable(el) && shown(el) && rect(el).width < innerWidth * 0.6);
      // The controls take a moment to mount and fade in after a wake. Presses made meanwhile wait for
      // them, rather than seeking.
      let waking = false, held = [];
      const focusControls = (tries = 0) => {
        const els = controls();
        if (!els.length) {
          if (tries < 8) return setTimeout(() => focusControls(tries + 1), 120);
          waking = false; held = [];
          return;
        }
        const bottom = Math.max(...els.map(e => rect(e).bottom));
        setCur(els.find(e => (e.dataset.uia || '').startsWith('control-play-pause'))
          || els.filter(e => rect(e).bottom > bottom - 20).sort((a, b) => rect(a).left - rect(b).left)[0]);
        waking = false;
        const queue = held;
        held = [];
        queue.forEach(press);
      };
      // Audio & subtitles, episodes and speed open a panel over the video and give it the page's focus.
      // Focus goes to its current choice; arrows move inside it, Select picks, and Back closes it the
      // way Netflix does, with Escape, and goes back to the control that opened it.
      const PANEL_ITEM = 'li[tabindex], button, [role="button"], [tabindex="0"]';
      const CHOSEN = '[data-uia*="selected"], [data-uia$="-active"], [aria-checked="true"], [aria-selected="true"], [aria-current="true"]';
      let panel = null, opener = null;
      const panelItems = () => panel ? [...panel.querySelectorAll(PANEL_ITEM)].filter(usable) : [];
      const openedPanel = () => {
        const a = document.activeElement;
        if (!a || a === document.body || a.closest('[data-uia^="control-"]')) return null;
        // The player itself takes focus too, and holds every control.
        if (a.querySelector('[data-uia^="control-play-pause"]') || !a.querySelector(PANEL_ITEM)) return null;
        return a;
      };
      // Some panels (episodes) are a listbox that moves its own highlight with the arrow keys.
      const ownKeys = () => panel && panel.isConnected && !panelItems().length;
      const intoPanel = () => {
        const items = panelItems();
        setCur(items.find(e => e.matches(CHOSEN) || e.querySelector(CHOSEN)) || items[0] || null, { quiet: true });
      };
      const closePanel = () => {
        const p = panel, back = opener;
        panel = opener = null;
        if (p && p.isConnected) p.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true, cancelable: true }));
        setCur(back && back.isConnected ? back : null, { quiet: true });
        return true;
      };

      // After a press: into a panel if one opens (or opens a level deeper), which Netflix gives focus
      // after a moment; meanwhile back to whatever is now where the pressed control was, since controls
      // swap elements (play becomes pause).
      const afterPress = (pt, pressed = cur, tries = 0) => setTimeout(() => {
        // Moved on since, unless the watcher only let go of a control Netflix swapped out.
        if (cur !== pressed && cur !== null) return;
        const p = openedPanel();
        if (p && p !== panel) {
          if (!panel) opener = pressed;
          panel = p;
          return intoPanel();
        }
        if (pressed.isConnected) { if (tries < 8) afterPress(pt, pressed, tries + 1); return; }
        if (panel && panel.isConnected) return intoPanel();
        if (panel) panel = opener = null;
        const best = controls().map(el => ({ el, d: Math.hypot(center(rect(el)).x - pt.x, center(rect(el)).y - pt.y) }))
          .sort((a, b) => a.d - b.d)[0];
        if (best && best.d < 80) setCur(best.el, { quiet: true });
      }, 100);

      const playerKey = e => {
        if (typing()) return;
        const dir = DIRS[e.key], swallow = () => { e.preventDefault(); e.stopImmediatePropagation(); };
        if (cur && !cur.isConnected && !panel) setCur(null);
        if (ownKeys() && (dir || e.key === 'Enter')) { wake(); return; }
        if (waking && (dir || e.key === 'Enter')) { swallow(); held.push(e.key); return; }
        if (!cur) {
          if (dir === 'up' || dir === 'down') { swallow(); wake(); waking = true; setTimeout(focusControls, 150); return; }
          if (e.key !== 'Enter') return;   // Left and Right seek, Netflix's own way
          const skip = [...document.querySelectorAll(PLAYER_BUTTONS)].find(usable);
          if (skip) { swallow(); skip.click(); }
          return;
        }
        if (!dir && e.key !== 'Enter') return;
        swallow();
        press(e.key);
      };
      const press = key => {
        if (!cur) return;
        wake();
        const dir = DIRS[key];
        if (dir) return stepControls(dir);
        const pt = center(rect(cur));
        cur.click();
        afterPress(pt);
      };
      const stepControls = dir => {
        if (panel) {
          if (!panel.isConnected) return closePanel();
          const els = panelItems();
          if (!els.includes(cur)) return intoPanel();
          if (dir === 'left' || dir === 'right') horizontal(dir, els, cur);
          else {
            const pick = nearestRow(els.filter(el => el !== cur), rect(cur), dir);
            if (pick) setCur(pick, { keepCol: true });
          }
          // Long lists (audio languages) scroll inside the panel.
          return cur && cur.scrollIntoView({ block: 'nearest' });
        }
        const els = controls();
        if (!els.includes(cur)) return setCur(null);
        if (dir === 'left' || dir === 'right') return horizontal(dir, els, cur);
        const pick = nearestRow(els.filter(el => el !== cur), rect(cur), dir);
        // Down from the bottom row gives the video back.
        if (pick) setCur(pick, { keepCol: true });
        else if (dir === 'down') setCur(null);
      };

      const big = (el, w, h) => { const r = rect(el); return r.width > w && r.height > h; };
      const modalRoot = () => [...document.querySelectorAll(MODAL)].find(m => big(m, 200, 100)) || null;
      // Menus can nest (a submenu opens beside its parent): the one holding focus, else the newest.
      const menuRoot = () => {
        const open = [...document.querySelectorAll(MENU)].filter(m => big(m, 20, 20) && getComputedStyle(m).visibility !== 'hidden');
        return open.find(m => m.contains(document.activeElement)) || open[open.length - 1] || null;
      };
      const closeModal = () => {
        const x = modal && modal.querySelector('[data-uia*="closebtn"], [data-uia*="close-button"], [aria-label="Close" i]');
        if (!x) return false;
        x.click();
        return true;
      };
      // Menus close on Escape, like any accessible menu; failing that, their button toggles them.
      const closeMenu = () => {
        const target = menu.contains(document.activeElement) ? document.activeElement : menu;
        target.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true, cancelable: true }));
        setTimeout(() => {
          if (!menu || !menu.isConnected || !big(menu, 20, 20)) return;
          const t = document.querySelector('[aria-expanded="true"][aria-haspopup]');
          if (t) t.click();
        }, 150);
        return true;
      };

      // Focus follows menus and the details panel: into them when they open, back to what opened them
      // when they close. Watching for them is simpler than knowing every way Netflix opens and closes them.
      const follow = (now, was, before, first) => {
        if (now === was) return before;
        if (now && !was) before = cur;
        if (now) {
          // A panel animates in from its tile, so pick by what's in it, not where it is (yet).
          setCur(first(), { quiet: true });
          return before;
        }
        const back = before && before.isConnected ? before : null;
        setCur(back, { quiet: true });
        // Closing the details panel leaves the page at the top, so the tile has to be brought back into
        // view, once Netflix is done scrolling.
        if (back) setTimeout(() => { if (cur === back) reveal(back); }, 250);
        return null;
      };
      setInterval(() => {
        // React rewrites class names when it re-renders an element, ring and all.
        if (ring && ring.isConnected && !ring.classList.contains('lazybones-focus')) {
          ring.classList.add('lazybones-focus');
          if (ring.matches(CARD)) ring.classList.add('lazybones-card');
        }
        if (onPlayer()) {
          modal = menu = null;
          if (panel && !panel.isConnected) return closePanel();
          // Netflix takes the controls off the page when they fade, focus and all.
          if (cur && (!cur.isConnected || !shown(cur))) setCur(null);
          return;
        }
        panel = opener = null;
        const m = modalRoot(), mm = menuRoot();
        if (mm !== menu) {
          const was = menu;
          menu = mm;
          beforeMenu = follow(mm, was, beforeMenu, () => firstFocus(candidates()));
        }
        if (m !== modal) {
          const was = modal;
          modal = m;
          if (!menu) beforeModal = follow(m, was, beforeModal, () => m.querySelector(PLAY) || firstFocus(candidates()));
          else if (!m) beforeModal = null;
        }
      }, 150);

      // Back: closes what Select opened, then returns to the top of the page. False lets Lazybones go to
      // the previous page, or Home.
      window.__lazybonesBack = () => {
        if (onPlayer()) {
          if (panel) return closePanel();
          if (!cur) return false;
          setCur(null);
          return true;
        }
        if (typing()) { document.activeElement.blur(); return true; }
        if (menu) return closeMenu();
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
