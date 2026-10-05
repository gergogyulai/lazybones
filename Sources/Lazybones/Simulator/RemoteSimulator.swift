import AppKit
import simd
import SiriRemote
import SwiftUI

/// A floating on-screen Siri Remote for development. Mouse and keyboard input go through the
/// same button semantics as the hardware: arrows auto-repeat, the TV button reports holds, and
/// dragging on the clickpad (or scrolling on a trackpad, or ⇧ arrows) swipes, with the finger's
/// rest tilting the focused icon as a thumb on the real touch surface does.
///
/// It also shows what the real remote and `Scripts/ctl.sh` send, lighting their buttons, so it
/// doubles as a monitor for the hardware.
@MainActor
final class RemoteSimulator: ObservableObject {
    enum Button: Hashable, CaseIterable {
        case up, down, left, right, select, back, home, playPause, volumeUp, volumeDown, mute, siri, power

        var command: RemoteCommand {
            switch self {
            case .up: .up
            case .down: .down
            case .left: .left
            case .right: .right
            case .select: .select
            case .back: .back
            case .home: .home
            case .playPause: .playPause
            case .volumeUp: .volumeUp
            case .volumeDown: .volumeDown
            case .mute: .mute
            case .siri: .siri
            case .power: .power
            }
        }

        /// The key printed on the button.
        var keyLabel: String {
            switch self {
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            case .select: "⏎"
            case .back: "esc"
            case .home: "H"
            case .playPause: "space"
            case .volumeUp: "="
            case .volumeDown: "-"
            case .mute: "M"
            case .siri: "S"
            case .power: "P"
            }
        }

        static let keys: [UInt16: Button] = [
            126: .up, 125: .down, 123: .left, 124: .right,
            36: .select, 76: .select, 53: .back, 51: .back, 4: .home, 49: .playPause,
            24: .volumeUp, 69: .volumeUp, 27: .volumeDown, 78: .volumeDown,
            46: .mute, 1: .siri, 35: .power,
        ]
    }

    /// The window's options, in UserDefaults.
    enum Preference {
        static let showsKeys = "remoteShowsKeys"
        static let showsEvents = "remoteShowsEvents"
        static let keepsOnTop = "remoteKeepsOnTop"
    }

    /// Where an event came from, for the readout under the remote.
    enum Origin { case simulator, hardware, control, phone }

    struct Echo: Identifiable, Equatable {
        let id: Int
        let text: String
        let origin: Origin
    }

    @Published private(set) var pressed: Set<Button> = []
    /// Buttons lit for a moment by an event from somewhere else: the real remote or `ctl.sh`.
    @Published private(set) var lit: Set<Button> = []
    /// The latest events, oldest first.
    @Published private(set) var echoes: [Echo] = []
    @Published var isVisible = false
    /// Whether a real remote is connected too, for the window's subtitle.
    @Published var hardware = SiriRemote.Status.Buttons.disconnected

    /// Where events go: the app, as if from the remote, but which macOS never acts on itself.
    var onEvent: ((RemoteEvent) -> Void)?
    /// Where a finger rests on the touch surface, as `TouchSurface.onRest` reports it.
    var onRest: ((SIMD2<Float>?) -> Void)?
    /// A finger on the clickpad, or two on the trackpad, moving: what `SiriRemote.onTouch` reports.
    var onTouch: ((TouchSample) -> Void)?
    /// A direction let go, as `SiriRemote.onRelease` reports it.
    var onRelease: ((RemoteCommand) -> Void)?
    /// Whether touch is moving a cursor right now, in which case it doesn't swipe.
    var touchMovesCursor: () -> Bool = { false }

    private var repeatTimer: Timer?
    private var holdTimer: Timer?
    private var panel: RemotePanel?
    private var nextEcho = 0
    private var scrolled = CGSize.zero
    /// Where two fingers scrolling on the trackpad would be on the touch surface.
    private var scrollFinger: SIMD2<Float>?
    /// Scroll distance per swipe step, in points: about what a two-finger flick covers.
    private let scrollStep: CGFloat = 36

    func isDown(_ b: Button) -> Bool { pressed.contains(b) || lit.contains(b) }

    private func send(_ event: RemoteEvent) {
        echo(event, from: .simulator)
        onEvent?(event)
    }

    // MARK: Events from elsewhere

    /// An event from the real remote or the iPhone, shown but not sent (the app already has it).
    func mirror(_ event: RemoteEvent, from origin: Origin = .hardware) {
        guard isVisible else { return }
        echo(event, from: origin)
        flash(event.command)
    }

    /// An event from `Scripts/ctl.sh`: shown, and sent as though pressed here.
    func inject(_ event: RemoteEvent) {
        echo(event, from: .control)
        flash(event.command)
        onEvent?(event)
    }

    private func flash(_ c: RemoteCommand) {
        guard let b = Button.allCases.first(where: { $0.command == c }) else { return }
        lit.insert(b)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            self?.lit.remove(b)
        }
    }

    private func echo(_ event: RemoteEvent, from origin: Origin) {
        guard isVisible else { return }
        let text = switch event.source {
        case .press: Self.name(event.command)
        case .repeat: "\(Self.name(event.command)) ⟳"
        case .hold: "hold \(Self.name(event.command))"
        case .swipe: "swipe \(Self.name(event.command))"
        }
        // Auto-repeats and long swipes would flood it; one line per run is enough.
        if let last = echoes.last, last.origin == origin, last.text == text, event.source == .repeat || event.source == .swipe {
            return
        }
        echoes.append(Echo(id: nextEcho, text: text, origin: origin))
        nextEcho += 1
        if echoes.count > 4 { echoes.removeFirst(echoes.count - 4) }
    }

    static func name(_ c: RemoteCommand) -> String {
        switch c {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .select: "select"
        case .back: "back"
        case .home: "TV"
        case .playPause: "play/pause"
        case .volumeUp: "volume +"
        case .volumeDown: "volume −"
        case .mute: "mute"
        case .siri: "Siri"
        case .power: "power"
        }
    }

    // MARK: Buttons

    func down(_ b: Button) {
        guard pressed.insert(b).inserted else { return }
        let c = b.command
        if c.isDirection {
            send(RemoteEvent(command: c, source: .press))
            repeatTimer?.invalidate()
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.startRepeating(c) }
            }
        } else if b == .home {
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.holdTimer = nil
                    self?.send(RemoteEvent(command: .home, source: .hold))
                }
            }
        } else {
            send(RemoteEvent(command: c, source: .press))
        }
    }

    func up(_ b: Button) {
        guard pressed.remove(b) != nil else { return }
        if b.command.isDirection {
            repeatTimer?.invalidate()
            repeatTimer = nil
            onRelease?(b.command)
        } else if b == .home, let t = holdTimer {
            t.invalidate()
            holdTimer = nil
            send(RemoteEvent(command: .home, source: .press))
        }
    }

    /// Two clicks of the TV button, close enough together to open the app switcher.
    func doubleClickHome() {
        tap(.home)
        tap(.home)
    }

    /// The TV button held long enough for Control Center, without waiting for it.
    func holdHome() {
        flash(.home)
        send(RemoteEvent(command: .home, source: .hold))
    }

    /// A click that's already over, e.g. a quick tap on the clickpad.
    func tap(_ b: Button) {
        down(b)
        up(b)
    }

    func swipe(_ c: RemoteCommand) {
        guard !touchMovesCursor() else { return }
        send(RemoteEvent(command: c, source: .swipe))
    }

    /// A finger on the touch surface (0...1, y up), as the hardware reports it.
    func touch(_ phase: TouchSample.Phase, at p: SIMD2<Float>) {
        onTouch?(TouchSample(phase, p, time: ProcessInfo.processInfo.systemUptime))
    }

    /// The finger's rest on the clickpad, in swipe steps from where focus last moved (y up).
    func rest(_ r: SIMD2<Float>?) {
        onRest?(r.map { simd_clamp($0, SIMD2(-1, -1), SIMD2(1, 1)) })
    }

    /// Scrolling over the remote: a trackpad's two fingers swipe, step by step as they travel, and
    /// tilt the focused icon in between; a mouse wheel's notches swipe one step each.
    func scroll(_ e: NSEvent) {
        // Momentum isn't a finger on the surface.
        guard e.momentumPhase.isEmpty else { return }
        // The way the fingers moved (y down), whichever way scrolling is set to go.
        let sign: CGFloat = e.isDirectionInvertedFromDevice ? 1 : -1
        let dx = sign * e.scrollingDeltaX, dy = sign * e.scrollingDeltaY
        if e.hasPreciseScrollingDeltas, touchMovesCursor() || scrollFinger != nil {
            return scrollTouch(e, dx: dx, dy: dy)
        }
        guard e.hasPreciseScrollingDeltas else {
            if abs(dy) >= abs(dx), dy != 0 { swipe(dy > 0 ? .down : .up) } else if dx != 0 { swipe(dx > 0 ? .right : .left) }
            return
        }
        if e.phase == .began || e.phase == .mayBegin { scrolled = .zero }
        scrolled.width += dx
        scrolled.height += dy
        if abs(scrolled.width) >= scrollStep, abs(scrolled.width) >= abs(scrolled.height) {
            swipe(scrolled.width > 0 ? .right : .left)
            scrolled = CGSize(width: scrolled.width - (scrolled.width > 0 ? scrollStep : -scrollStep), height: 0)
        } else if abs(scrolled.height) >= scrollStep {
            swipe(scrolled.height > 0 ? .down : .up)
            scrolled = CGSize(width: 0, height: scrolled.height - (scrolled.height > 0 ? scrollStep : -scrollStep))
        }
        if e.phase == .ended || e.phase == .cancelled {
            scrolled = .zero
            rest(nil)
        } else {
            rest(SIMD2(Float(scrolled.width / scrollStep), Float(-scrolled.height / scrollStep)))
        }
    }

    /// Two fingers on the trackpad as one on the touch surface, starting from its centre, so they
    /// move a cursor as the thumb would: about a third of the surface per inch of travel.
    private func scrollTouch(_ e: NSEvent, dx: CGFloat, dy: CGFloat) {
        let perPoint: Float = 1 / 240
        if e.phase == .began || e.phase == .mayBegin || scrollFinger == nil {
            let p = SIMD2<Float>(0.5, 0.5)
            scrollFinger = p
            touch(.began, at: p)
        }
        guard var p = scrollFinger else { return }
        p += SIMD2(Float(dx), Float(-dy)) * perPoint
        scrollFinger = p
        if e.phase == .ended || e.phase == .cancelled {
            touch(.ended, at: p)
            scrollFinger = nil
        } else {
            touch(.moved, at: p)
        }
    }

    func releaseAll() {
        pressed.forEach(up)
    }

    private func startRepeating(_ c: RemoteCommand) {
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(RemoteEvent(command: c, source: .repeat)) }
        }
    }

    // MARK: Window

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if panel == nil {
            let host = NSHostingController(rootView: RemoteWindowContent().environmentObject(self))
            // Sized by constraints, not `preferredContentSize`: with the unified toolbar the window
            // and the preferred size chase each other until AppKit gives up and throws.
            host.sizingOptions = .intrinsicContentSize
            // The content runs under the title bar and draws its own; no inset for it.
            host.safeAreaRegions = []
            let p = RemotePanel(simulator: self, contentSize: host.view.fittingSize)
            p.contentViewController = host
            // Where it was last left (only its place: the size is the content's), or else next to
            // Lazybones's own window, which may not be on the main screen.
            let size = p.frame.size
            if p.setFrameUsingName(RemotePanel.frameName) {
                p.setFrame(NSRect(origin: NSPoint(x: p.frame.minX, y: p.frame.maxY - size.height), size: size), display: false)
            } else {
                let main = NSApp.windows.first { !($0 is NSPanel) && $0.isVisible }
                if let screen = (main?.screen ?? NSScreen.main)?.visibleFrame {
                    p.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 40, y: screen.midY - size.height / 2))
                }
            }
            p.setFrameAutosaveName(RemotePanel.frameName)
            panel = p
        }
        panel?.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func hide() {
        releaseAll()
        rest(nil)
        echoes = []
        panel?.orderOut(nil)
        isVisible = false
    }

    func panelClosed() {
        releaseAll()
        rest(nil)
        echoes = []
        isVisible = false
    }
}
