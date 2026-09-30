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
        case .playPause: togglePlayback(s)
        default: break
        }
    }

    /// Leaves the page's own full-screen mode (a video's), if it's in it, and runs `done` once the
    /// window is back. WebKit gives a full-screen page a window of its own, which would otherwise
    /// stay over everything while the app shrinks away underneath it.
    func leaveFullscreen(_ s: Service, then done: @escaping () -> Void) {
        guard let wv = views[s.id], wv.fullscreenState != .notInFullscreen else { return done() }
        wv.evaluateJavaScript(Scripts.exitFullscreen)
        Task { @MainActor in
            for _ in 0..<30 where wv.fullscreenState != .notInFullscreen {
                try? await Task.sleep(for: .milliseconds(50))
            }
            done()
        }
    }

    /// Back inside a page. `done` says whether something took it; false means there was nowhere
    /// to go back to, and the caller should go Home.
    ///
    /// Sites with a TV interface own their back stack (closing a menu, leaving a player), so they
    /// get the key and Back only counts if they reacted. Ordinary sites go to the previous page.
    func back(from s: Service, then done: @escaping (Bool) -> Void) {
        guard let wv = views[s.id] else { return done(false) }
        if wv.fullscreenState != .notInFullscreen {
            wv.evaluateJavaScript(Scripts.exitFullscreen)
            return done(true)
        }
        guard ServiceModules.module(for: s).handlesNavigation || s.agent == .tv else {
            // A page with its own navigation script gets to close what it opened first.
            wv.evaluateJavaScript(Scripts.pageBack) { handled, _ in
                if handled as? Bool == true { return done(true) }
                guard wv.canGoBack else { return done(false) }
                wv.goBack()
                done(true)
            }
            return
        }
        wv.evaluateJavaScript(Scripts.watchStart) { [weak self] _, _ in
            self?.send(.back, to: s)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                wv.evaluateJavaScript(Scripts.watchEnd) { reacted, _ in done(reacted as? Bool == true) }
            }
        }
    }

    /// Calls `__lazybonesKB[fn](arg)` in the page, which edits the focused field and returns its new value.
    func keyboard(_ fn: String, _ arg: Any? = nil, in s: Service, then done: ((Any?) -> Void)? = nil) {
        guard let wv = views[s.id] else { return }
        wv.callAsyncJavaScript("const kb = window.__lazybonesKB; return kb ? kb[fn](arg) : null;",
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
