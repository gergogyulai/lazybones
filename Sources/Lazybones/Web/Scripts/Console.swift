extension Scripts {
    /// Forwards what the page writes to its console, plus uncaught errors and unhandled promise
    /// rejections, to the app's log via `webkit.messageHandlers.lazybonesConsole`, so a site hack
    /// breaking shows up without Safari's inspector attached. Warnings and errors only, unless
    /// `everything` (`--page-log`). Capped per page, since a broken site can log in a loop.
    static func console(everything: Bool) -> String {
        """
        (() => {
          if (window.top !== window || window.__lazybonesConsole) return;
          window.__lazybonesConsole = true;
          const all = \(everything);
          let sent = 0, last = '', repeats = 0;
          const limit = 200;
          const text = a => {
            if (a instanceof Error) return a.stack ? a.name + ': ' + a.message + '\\n' + a.stack.split('\\n').slice(0, 3).join('\\n') : String(a);
            if (typeof a === 'string') return a;
            try { return JSON.stringify(a); } catch (_) { return String(a); }
          };
          const post = (level, args) => {
            if (sent >= limit) return;
            let msg;
            try { msg = Array.from(args, text).join(' ').slice(0, 1000); } catch (_) { return; }
            if (msg === last) { repeats++; return; }
            if (repeats) { send('info', '(last message repeated ' + repeats + ' more times)'); repeats = 0; }
            last = msg;
            send(level, msg);
            if (sent === limit) send('warn', 'console: ' + limit + ' messages, not forwarding any more from this page');
          };
          const send = (level, msg) => {
            sent++;
            try { webkit.messageHandlers.lazybonesConsole.postMessage({ level, msg }); } catch (_) {}
          };
          const levels = all ? ['error', 'warn', 'info', 'log', 'debug'] : ['error', 'warn'];
          for (const level of levels) {
            const original = console[level];
            if (typeof original !== 'function') continue;
            console[level] = function () {
              post(level, arguments);
              return original.apply(this, arguments);
            };
          }
          window.addEventListener('error', e => {
            // Resource load errors (an <img> 404) bubble here too, without a message.
            if (!e.message) return;
            const where = /^https?:/.test(e.filename) ? ' (' + e.filename.split('?')[0] + ':' + e.lineno + ')' : '';
            post('error', ['uncaught: ' + e.message + where]);
          });
          window.addEventListener('unhandledrejection', e => post('error', ['unhandled rejection:', e.reason]));
        })();
        """
    }
}
