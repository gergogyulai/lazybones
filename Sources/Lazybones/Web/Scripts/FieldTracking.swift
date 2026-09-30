extension Scripts {
    /// Tells the app which text field has focus and what it's for, so the on-screen keyboard can
    /// show and adapt, and exposes `__lazybonesKB` for the keyboard to edit it.
    static let keyboard = #"""
    (() => {
      if (window.top !== window || window.__lazybonesKB) return;
      const post = m => { try { webkit.messageHandlers.lazybonesKeyboard.postMessage(m); } catch (_) {} };
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
      window.__lazybonesKB = KB;
    })();
    """#
}
