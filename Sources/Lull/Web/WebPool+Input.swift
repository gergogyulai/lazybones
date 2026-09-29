import AppKit
import SiriRemote
import WebKit

/// Getting remote presses and keyboard edits into a page.
extension WebPool {
    func send(_ command: RemoteCommand, to s: Service) {
        guard let wv = views[s.id], let win = wv.window else { return }
        if win.firstResponder !== wv { win.makeFirstResponder(wv) }
        switch command {
        case .up: SyntheticKeys.press(.up, in: win)
        case .down: SyntheticKeys.press(.down, in: win)
        case .left: SyntheticKeys.press(.left, in: win)
        case .right: SyntheticKeys.press(.right, in: win)
        case .select: SyntheticKeys.press(.select, in: win)
        case .back: SyntheticKeys.press(.back, in: win)
        case .playPause:
            let id = s.id
            wv.evaluateJavaScript(Scripts.playPause) { [weak self] result, _ in
                self?.onReport?(id, "play/pause", "\(result ?? "error")")
            }
        default: break
        }
    }

    /// Calls `__lullKB[fn](arg)` in the page, which edits the focused field and returns its new value.
    func keyboard(_ fn: String, _ arg: Any? = nil, in s: Service, then done: ((Any?) -> Void)? = nil) {
        guard let wv = views[s.id] else { return }
        wv.callAsyncJavaScript("const kb = window.__lullKB; return kb ? kb[fn](arg) : null;",
                               arguments: ["fn": fn, "arg": arg ?? NSNull()], in: nil, in: .page) { result in
            if case let .success(v) = result { done?(v) }
        }
    }

    /// A real Return key press, so forms submit the way they would from a keyboard.
    func pressReturn(_ s: Service) {
        guard let wv = views[s.id], let win = wv.window else { return }
        if win.firstResponder !== wv { win.makeFirstResponder(wv) }
        SyntheticKeys.press(.select, in: win)
    }
}
