extension Scripts {
    /// For pages driven by the cursor: `__lazybonesTargets()` lists what can be clicked on screen,
    /// as `[left, top, width, height, ...]` in CSS pixels from the viewport's corner, for the cursor to
    /// snap to (see `CursorMotion`). Things another element covers, like the page behind a dialog, are
    /// left out. Mouse-first sites make plenty of plain elements clickable, so besides links, buttons
    /// and roles, anything styled with a pointer cursor counts too, as far as a few milliseconds allow.
    static let cursorTargets = #"""
    (() => {
      if (window.top !== window || window.__lazybonesTargets) return;
      const SEL = 'a[href],button,input:not([type="hidden"]),select,textarea,summary,label[for],[onclick],'
        + '[contenteditable=""],[contenteditable="true"],[tabindex]:not([tabindex="-1"]),'
        + '[role="button"],[role="link"],[role="tab"],[role="menuitem"],[role="menuitemcheckbox"],'
        + '[role="menuitemradio"],[role="option"],[role="checkbox"],[role="radio"],[role="switch"],'
        + '[role="slider"],[role="treeitem"]';
      const LOOSE = 'div,span,li,img,svg,figure,article,section';

      const visible = (el, r) => {
        if (r.width < 6 || r.height < 6) return false;
        if (r.bottom <= 0 || r.right <= 0 || r.top >= innerHeight || r.left >= innerWidth) return false;
        if (el.disabled || el.closest('[aria-hidden="true"],[inert]')) return false;
        // Covered by something else, judged at the middle of its visible part.
        const x = (Math.max(r.left, 0) + Math.min(r.right, innerWidth)) / 2;
        const y = (Math.max(r.top, 0) + Math.min(r.bottom, innerHeight)) / 2;
        const hit = document.elementFromPoint(x, y);
        return !!hit && (el === hit || el.contains(hit));
      };

      window.__lazybonesTargets = () => {
        const out = [], seen = new Set();
        const add = (el, r) => {
          const key = Math.round(r.left / 3) + ',' + Math.round(r.top / 3) + ',' + Math.round(r.width / 3) + ',' + Math.round(r.height / 3);
          if (seen.has(key)) return;
          seen.add(key);
          out.push(Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height));
        };
        for (const el of document.querySelectorAll(SEL)) {
          const r = el.getBoundingClientRect();
          if (visible(el, r)) add(el, r);
        }
        const deadline = performance.now() + 8;
        let n = 0;
        for (const el of document.querySelectorAll(LOOSE)) {
          if ((++n & 63) === 0 && performance.now() > deadline) break;
          const r = el.getBoundingClientRect();
          if (r.bottom <= 0 || r.top >= innerHeight || r.width < 6 || r.height < 6) continue;
          if (getComputedStyle(el).cursor !== 'pointer') continue;
          // Only where the pointer style starts, not every child that inherits it.
          const parent = el.parentElement;
          if (parent && getComputedStyle(parent).cursor === 'pointer') continue;
          if (visible(el, r)) add(el, r);
        }
        return out;
      };
    })();
    """#
}
