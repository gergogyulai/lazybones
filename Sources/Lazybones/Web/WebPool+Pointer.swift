import AppKit
import WebKit

/// A pointer in a page: real mouse and scroll wheel events, sent straight to the web view, so the
/// page sees trusted events, hover styles apply, and a scroll goes to whatever is under the pointer.
/// Points are in the web view's own coordinates, which run from its top left corner like the page's.
extension WebPool {
    enum MouseAction { case move, down, up }

    func mouse(_ action: MouseAction, at point: CGPoint, in s: Service) {
        guard let wv = views[s.id], let window = wv.window else { return }
        let type: NSEvent.EventType = switch action {
        case .move: .mouseMoved
        case .down: .leftMouseDown
        case .up: .leftMouseUp
        }
        guard let event = NSEvent.mouseEvent(
            with: type, location: wv.convert(point, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: action == .down ? 1 : 0
        ) else { return }
        if action != .move, window.firstResponder !== wv { window.makeFirstResponder(wv) }
        switch action {
        case .move: wv.mouseMoved(with: event)
        case .down: wv.mouseDown(with: event)
        case .up: wv.mouseUp(with: event)
        }
    }

    /// A click at `point`: over it, down, and up a moment later. WebKit drops a press whose release
    /// follows it too closely, so this waits between them; `done` runs once the button is up.
    func click(at point: CGPoint, in s: Service, then done: (() -> Void)? = nil) {
        mouse(.move, at: point, in: s)
        mouse(.down, at: point, in: s)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.mouse(.up, at: point, in: s)
            done?()
        }
    }

    /// Scrolls what's under `point` by whole pixels; positive `dy` goes further down the page.
    func scroll(dx: Int, dy: Int, at point: CGPoint, in s: Service) {
        guard let wv = views[s.id], wv.window != nil, dx != 0 || dy != 0,
              let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(-dy), wheel2: Int32(-dx), wheel3: 0) else { return }
        // An event made from a CGEvent has no window, so its location in the window is read from the
        // screen location: give it the window point, flipped as screen coordinates are.
        let p = wv.convert(point, to: nil)
        cg.location = CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
        guard let event = NSEvent(cgEvent: cg) else { return }
        wv.scrollWheel(with: event)
    }

    /// What can be clicked in the page right now (`Scripts.cursorTargets`), in the web view's points.
    func pointerTargets(in s: Service, then done: @escaping ([CGRect]) -> Void) {
        guard let wv = views[s.id] else { return done([]) }
        let scale = wv.pageZoom * wv.magnification
        wv.evaluateJavaScript("window.__lazybonesTargets ? window.__lazybonesTargets() : []") { result, _ in
            let n = (result as? [NSNumber])?.map { CGFloat($0.doubleValue) * scale } ?? []
            done(stride(from: 0, to: n.count - 3, by: 4).map { CGRect(x: n[$0], y: n[$0 + 1], width: n[$0 + 2], height: n[$0 + 3]) })
        }
    }

    /// Whether the page has something (a video) in its own full screen, in a window of its own.
    func isFullscreen(_ s: Service) -> Bool { views[s.id].map { $0.fullscreenState != .notInFullscreen } ?? false }

    /// Where the service's page sits in its window, from the window's top left corner. Windowed, the
    /// page starts below the title bar, while views drawn over it may not.
    func frameInWindow(of s: Service) -> CGRect? {
        guard let wv = views[s.id], let content = wv.window?.contentView else { return nil }
        let r = wv.convert(wv.bounds, to: content)
        return content.isFlipped ? r : CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    /// The size of the service's page on screen, in points.
    func viewportSize(of s: Service) -> CGSize? { views[s.id]?.bounds.size }
}
