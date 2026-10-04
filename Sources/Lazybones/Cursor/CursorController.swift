import AppKit
import SiriRemote
import SwiftUI

/// The cursor in apps set to `Navigation.cursor`: takes touches and clickpad presses, moves the
/// pointer (`CursorMotion`), turns circling the ring into scrolling (`TouchGestures`, `RingScroll`),
/// and puts it all into the page as real mouse and scroll wheel events. `CursorView` draws it.
///
/// It runs a frame loop only while something is moving, and fades out after a few idle seconds.
/// While it's hidden over a playing video, the clickpad goes to the page as keys again, so the
/// player's own seeking works; a touch or a click brings the cursor back.
@MainActor
final class CursorController: ObservableObject {
    /// What `CursorView` draws: all in the page's points.
    struct Appearance: Equatable {
        var point = CGPoint.zero
        /// The outline drawn around what it's over, and how far the cursor has turned into it (0...1).
        var highlight = CGRect.zero
        var morph: CGFloat = 0
        var diameter: CGFloat = 30
        var visible = false
        var pressed = false
        /// Where the page sits in the window, which the points above are relative to.
        var page = CGRect.zero
    }

    @Published private(set) var appearance = Appearance()
    /// The app it's in, while that app uses the cursor.
    @Published private(set) var serviceID: String?

    /// The saved settings for an app, which can change while it's open.
    var service: (String) -> Service? = { _ in nil }
    /// Whether an app's page is playing something, so a hidden cursor can let the player have the clickpad.
    var isPlaying: (String) -> Bool = { _ in false }

    private let web: WebPool
    private var motion = CursorMotion()
    private var gestures = TouchGestures()
    private var scroll = RingScroll()
    /// Where it was left in each app, to come back to.
    private var places: [String: CGPoint] = [:]

    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var hideTask: Task<Void, Never>?
    private var lastInput: TimeInterval = 0
    /// Its place in a page not laid out yet: the middle, once there's a size to find it from.
    private var centresOnLayout = false
    private var lastTouch: TimeInterval?
    private var glide: (direction: RemoteCommand, since: TimeInterval)?
    private var lastTargets: TimeInterval = 0
    private var fetchingTargets = false
    private var sentPoint: CGPoint?
    /// Recent places it showed, for a click to land where it was just before the press.
    private var trail: [(time: TimeInterval, point: CGPoint)] = []
    private var rendered = CGPoint.zero
    private var renderedHighlight = CGRect.zero
    private var morph: CGFloat = 0

    /// Seconds without input before it fades.
    static let idleTimeout: TimeInterval = 4

    init(web: WebPool) {
        self.web = web
    }

    private var current: Service? { serviceID.flatMap(service) }
    private var settings: CursorSettings {
        var s = current?.cursor ?? CursorSettings()
        if !s.followsTouch, !s.followsArrows { s.followsTouch = true }
        return s
    }

    /// Whether touches move it (otherwise they swipe, and the page gets arrow keys).
    var takesTouch: Bool { serviceID != nil && settings.followsTouch && !inFullscreen }

    private var inFullscreen: Bool { current.map(web.isFullscreen) ?? false }

    // MARK: Apps

    /// The app the remote now drives: the cursor shows in it if it uses one, and goes otherwise.
    func attach(_ s: Service?) {
        let id = s.flatMap { ServiceModules.navigation(for: $0) == .cursor ? $0.id : nil }
        guard id != serviceID else { return }
        if let old = serviceID { places[old] = motion.raw }
        serviceID = id
        stopMoving()
        scroll.stop()
        sentPoint = nil
        motion.targets = []
        guard let id else {
            hide()
            stopTimer()
            return
        }
        centresOnLayout = places[id] == nil
        updateBounds()
        if let place = places[id] { motion.place(at: place) } else { centreIfLaidOut() }
        rendered = motion.snap.point
        appearance.point = rendered
        morph = 0
        show()
    }

    // MARK: Input

    func touch(_ sample: TouchSample) {
        guard let s = current, takesTouch else { return }
        let settings = settings
        motion.settings = settings
        gestures.ringEnabled = settings.ringScrolls
        if sample.phase == .began {
            scroll.stop()
            glide = nil
            show()
            refreshTargets(s)
        }
        let dt = lastTouch.map { sample.time - $0 } ?? 1 / 120
        lastTouch = sample.phase == .ended ? nil : sample.time
        for output in gestures.handle(sample) {
            switch output {
            case let .move(delta):
                let overflow = motion.touchMove(delta, dt: dt)
                if overflow != 0 { scroll.add(Double(overflow) * 1.5) }
            case let .turn(radians):
                scroll.add(RingScroll.pixels(radians, height: motion.bounds.height, settings: settings))
            case let .turnEnded(velocity):
                if settings.scrollMomentum {
                    scroll.release(RingScroll.pixels(velocity, height: motion.bounds.height, settings: settings),
                                   height: motion.bounds.height)
                }
            }
        }
        if sample.phase != .ended { show() }
        wake()
    }

    /// A press on the clickpad, or a swipe. Returns false for what the page should have instead.
    func handle(_ event: RemoteEvent) -> Bool {
        guard let s = current else { return false }
        let settings = settings
        motion.settings = settings
        let command = event.command
        // Over a full-screen or playing video, a hidden cursor leaves the clickpad to the player.
        let hidden = !appearance.visible
        if inFullscreen || (hidden && isPlaying(s.id) && command != .select) { return false }
        switch command {
        case .select:
            if hidden {
                // Back where it was, over whatever it was over: a player shows its controls.
                show()
                sendMove(force: true)
                return true
            }
            click(in: s)
            return true
        case .up, .down, .left, .right:
            guard settings.followsArrows || event.source == .swipe else { return false }
            show()
            refreshTargets(s)
            switch event.source {
            case .repeat:
                if glide?.direction != command { glide = (command, ProcessInfo.processInfo.systemUptime) }
            case .press, .swipe:
                // The first press after it has faded only shows where it is.
                guard !hidden else { return true }
                glide = nil
                let overflow = motion.nudge(command)
                if overflow != 0 { scroll.add(Double(overflow)) }
            case .hold:
                break
            }
            wake()
            return true
        default:
            return false
        }
    }

    /// A direction let go: a glide stops where it is.
    func release(_ command: RemoteCommand) {
        guard glide?.direction == command else { return }
        glide = nil
        if let s = current { refreshTargets(s) }
        show()
    }

    private func click(in s: Service) {
        // Pressing the clickpad rocks the thumb on the touch surface just before the button
        // registers; click where the cursor was a moment before, if it hasn't gone far since.
        let now = ProcessInfo.processInfo.systemUptime
        var point = motion.snap.point
        if let before = trail.last(where: { now - $0.time >= 0.07 }), now - before.time < 0.25,
           hypot(before.point.x - point.x, before.point.y - point.y) < 24 * motion.unit {
            point = before.point
        }
        appearance.pressed = true
        show()
        web.click(at: point, in: s) { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                self?.appearance.pressed = false
                // A click often changes the page: a menu opens, a dialog appears.
                try? await Task.sleep(for: .milliseconds(300))
                if let self, let s = self.current { self.refreshTargets(s, force: true) }
            }
        }
    }

    // MARK: Showing and hiding

    private func show() {
        lastInput = ProcessInfo.processInfo.systemUptime
        if !appearance.visible {
            withAnimation(Motion.crossfade) { appearance.visible = true }
            // The Mac's own pointer has no business on the TV.
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        guard hideTask == nil else { return }
        hideTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let wait = lastInput + Self.idleTimeout - ProcessInfo.processInfo.systemUptime
                // A finger resting on the surface, or a held direction, isn't idle.
                if wait > 0 || glide != nil || lastTouch != nil {
                    try? await Task.sleep(for: .seconds(max(wait, 0.5)))
                    continue
                }
                hide()
                return
            }
        }
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        if appearance.visible { withAnimation(Motion.crossfade) { appearance.visible = false } }
    }

    private func stopMoving() {
        glide = nil
        lastTouch = nil
        gestures = TouchGestures()
    }

    // MARK: Frames

    private func wake() {
        guard timer == nil, serviceID != nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let s = current else { return stopTimer() }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 1 / 20)
        lastTick = now
        updateBounds()
        motion.settings = settings

        if let g = glide {
            let overflow = motion.glide(g.direction, held: now - g.since, dt: dt)
            if overflow != 0 { scroll.add(Double(overflow)) }
            // A lost release mustn't glide forever: the remote repeats every 0.11s while held.
            if now - g.since > 30 { glide = nil }
        }
        let snap = motion.snap
        let pixels = scroll.step(dt)
        if pixels != 0 {
            web.scroll(dx: 0, dy: pixels, at: snap.point, in: s)
        }
        if glide != nil || lastTouch != nil || pixels != 0 { refreshTargets(s) }
        sendMove()

        trail.append((now, snap.point))
        trail.removeAll { now - $0.time > 0.2 }

        // The drawn cursor eases after the real one, and turns into an outline over a button.
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let follow = reduce ? 1 : CGFloat(1 - exp(-dt * 30))
        rendered.x += (snap.point.x - rendered.x) * follow
        rendered.y += (snap.point.y - rendered.y) * follow
        let outline = snap.target.flatMap(outlined)
        if let outline {
            renderedHighlight = morph < 0.01 ? CGRect(origin: rendered, size: .zero) : renderedHighlight
            renderedHighlight = Self.mix(renderedHighlight, outline.insetBy(dx: -6 * motion.unit, dy: -6 * motion.unit), follow)
        }
        let morphRate = reduce ? 1 : CGFloat(1 - exp(-dt * 22))
        morph += ((outline == nil ? 0 : 1) - morph) * morphRate
        if abs(morph - (outline == nil ? 0 : 1)) < 0.005 { morph = outline == nil ? 0 : 1 }

        appearance.point = rendered
        appearance.highlight = renderedHighlight
        appearance.morph = morph
        appearance.diameter = Self.diameter(settings.size) * motion.unit
        if let frame = web.frameInWindow(of: s) { appearance.page = frame }

        let settled = hypot(snap.point.x - rendered.x, snap.point.y - rendered.y) < 0.3
            && (morph == 0 || morph == 1) && (outline == nil || Self.close(renderedHighlight, outline!.insetBy(dx: -6 * motion.unit, dy: -6 * motion.unit)))
        if settled { rendered = snap.point }
        if settled, glide == nil, lastTouch == nil, scroll.isIdle { stopTimer() }
    }

    /// The outline is for buttons and links; something card-sized or bigger keeps the round cursor.
    private func outlined(_ r: CGRect) -> CGRect? {
        r.width <= motion.bounds.width * 0.35 && r.height <= motion.bounds.height * 0.3 ? r : nil
    }

    private func sendMove(force: Bool = false) {
        guard let s = current else { return }
        let p = motion.snap.point
        if !force, let sent = sentPoint, hypot(sent.x - p.x, sent.y - p.y) < 0.5 { return }
        sentPoint = p
        web.mouse(.move, at: p, in: s)
    }

    private func refreshTargets(_ s: Service, force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || (!fetchingTargets && now - lastTargets > 0.25) else { return }
        lastTargets = now
        fetchingTargets = true
        web.pointerTargets(in: s) { [weak self] rects in
            guard let self else { return }
            fetchingTargets = false
            guard serviceID == s.id else { return }
            motion.targets = rects
            wake()
        }
    }

    private func updateBounds() {
        if let s = current, let size = web.viewportSize(of: s), size.width > 0, size != motion.bounds {
            motion.bounds = size
        }
        centreIfLaidOut()
    }

    private func centreIfLaidOut() {
        guard centresOnLayout, let s = current, let size = web.viewportSize(of: s), size.width > 0 else { return }
        centresOnLayout = false
        motion.place(at: CGPoint(x: size.width / 2, y: size.height / 2))
        rendered = motion.snap.point
    }

    static func diameter(_ size: CursorSettings.Size) -> CGFloat {
        switch size {
        case .small: 24
        case .medium: 34
        case .large: 46
        }
    }

    private static func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.3 && abs(a.minY - b.minY) < 0.3 && abs(a.width - b.width) < 0.3 && abs(a.height - b.height) < 0.3
    }
}
