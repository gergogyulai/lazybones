extension Scripts {
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
}
