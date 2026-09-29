import AppKit
import SiriRemote
import SwiftUI

/// A floating on-screen Siri Remote for development. Mouse and keyboard input go through the
/// same button semantics as the hardware: arrows auto-repeat, the TV button reports holds, and
/// dragging on the clickpad swipes.
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

    @Published private(set) var pressed: Set<Button> = []
    @Published var isVisible = false

    private let send: (RemoteEvent) -> Void
    private var repeatTimer: Timer?
    private var holdTimer: Timer?
    private var panel: RemotePanel?

    init(send: @escaping (RemoteEvent) -> Void) {
        self.send = send
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
        } else if b == .home, let t = holdTimer {
            t.invalidate()
            holdTimer = nil
            send(RemoteEvent(command: .home, source: .press))
        }
    }

    /// A click that's already over, e.g. a quick tap on the clickpad.
    func tap(_ b: Button) {
        down(b)
        up(b)
    }

    func swipe(_ c: RemoteCommand) {
        send(RemoteEvent(command: c, source: .swipe))
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
            let p = RemotePanel(simulator: self)
            p.setContentSize(NSSize(width: RemoteView.windowSize.width, height: RemoteView.windowSize.height))
            p.contentView = NSHostingView(rootView: RemoteView().environmentObject(self))
            // Where it was last left, or else next to Lull's own window (which may not be on the main screen).
            if !p.setFrameUsingName(RemotePanel.frameName) {
                let host = NSApp.windows.first { !($0 is NSPanel) && $0.isVisible }
                if let screen = (host?.screen ?? NSScreen.main)?.visibleFrame {
                    p.setFrameOrigin(NSPoint(x: screen.maxX - p.frame.width - 40, y: screen.midY - p.frame.height / 2))
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
        panel?.orderOut(nil)
        isVisible = false
    }

    fileprivate func panelClosed() {
        releaseAll()
        isVisible = false
    }
}

/// Floats above everything, including Lull in full screen, and turns keys into button presses.
final class RemotePanel: NSPanel, NSWindowDelegate {
    static let frameName = "RemoteSimulator"
    private weak var simulator: RemoteSimulator?

    init(simulator: RemoteSimulator) {
        self.simulator = simulator
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Remote"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let b = button(for: event) else { return super.keyDown(with: event) }
        if !event.isARepeat { MainActor.assumeIsolated { simulator?.down(b) } }
    }

    override func keyUp(with event: NSEvent) {
        guard let b = button(for: event) else { return super.keyUp(with: event) }
        MainActor.assumeIsolated { simulator?.up(b) }
    }

    override func resignKey() {
        super.resignKey()
        // Key-ups go to whichever window is key, so don't leave a button stuck down.
        MainActor.assumeIsolated { simulator?.releaseAll() }
    }

    func windowWillClose(_: Notification) {
        MainActor.assumeIsolated { simulator?.panelClosed() }
    }

    private func button(for event: NSEvent) -> RemoteSimulator.Button? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        return RemoteSimulator.Button.keys[event.keyCode]
    }
}

// MARK: - View

/// The 2021+ Siri Remote: aluminium body, black clickpad and buttons, Siri on the right side.
struct RemoteView: View {
    static let windowSize = CGSize(width: 210, height: 600)

    @EnvironmentObject var sim: RemoteSimulator

    private let bodySize = CGSize(width: 150, height: 520)
    private let button: CGFloat = 46
    private let gap: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topTrailing) {
            remoteBody
            // Siri, on the right edge.
            SideButton(pressed: sim.pressed.contains(.siri))
                .offset(x: 4, y: 180)
                .pressable(.siri, sim)
            Text(RemoteSimulator.Button.siri.keyLabel)
                .imprint(onDark: false)
                .offset(x: -8, y: 212)
        }
        .frame(width: bodySize.width + 4, height: bodySize.height)
        .padding(.top, 36)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .top)
    }

    private var remoteBody: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(RemoteSimulator.Button.power.keyLabel).imprint(onDark: false)
                RoundButton(symbol: "power", key: nil, size: 24, pressed: sim.pressed.contains(.power))
                    .pressable(.power, sim)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Clickpad()
                .padding(.top, 10)

            HStack(alignment: .top, spacing: gap * 2) {
                VStack(spacing: gap) {
                    round(.back, "chevron.left")
                    round(.playPause, "playpause.fill")
                    round(.mute, "speaker.slash.fill")
                }
                VStack(spacing: gap) {
                    round(.home, "tv")
                    VolumeRocker(width: button, height: button * 2 + gap)
                }
            }
            .padding(.top, 26)

            Spacer()
            Text("lull")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.18))
                .padding(.bottom, 26)
        }
        .frame(width: bodySize.width, height: bodySize.height)
        .background {
            shape
                .fill(LinearGradient(stops: [
                    .init(color: Color(white: 0.74), location: 0),
                    .init(color: Color(white: 0.9), location: 0.18),
                    .init(color: Color(white: 0.95), location: 0.5),
                    .init(color: Color(white: 0.86), location: 0.85),
                    .init(color: Color(white: 0.7), location: 1),
                ], startPoint: .leading, endPoint: .trailing))
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.08)],
                                                   startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .overlay(shape.stroke(.black.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                // Drag the aluminium to move the remote; buttons and the clickpad keep their own gestures.
                .gesture(WindowDragGesture())
        }
    }

    private func round(_ b: RemoteSimulator.Button, _ symbol: String) -> some View {
        RoundButton(symbol: symbol, key: b.keyLabel, size: button, pressed: sim.pressed.contains(b))
            .pressable(b, sim)
    }
}

private struct RoundButton: View {
    let symbol: String
    let key: String?
    let size: CGFloat
    let pressed: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: pressed ? [Color(white: 0.05), Color(white: 0.1)]
                                                     : [Color(white: 0.2), Color(white: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(pressed ? 0.04 : 0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(pressed ? 0.1 : 0.35), radius: pressed ? 0.5 : 1.5, y: pressed ? 0 : 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .offset(y: key == nil ? 0 : -3)
            if let key {
                Text(key).imprint().offset(y: size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(pressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

private struct VolumeRocker: View {
    @EnvironmentObject var sim: RemoteSimulator
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let upPressed = sim.pressed.contains(.volumeUp)
        let downPressed = sim.pressed.contains(.volumeDown)
        VStack(spacing: 0) {
            half("plus", RemoteSimulator.Button.volumeUp, pressed: upPressed)
            half("minus", RemoteSimulator.Button.volumeDown, pressed: downPressed)
        }
        .frame(width: width, height: height)
        .background(
            Capsule().fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        )
        .clipShape(Capsule())
        // Rocks toward the pressed end.
        .rotation3DEffect(.degrees(upPressed ? 6 : downPressed ? -6 : 0), axis: (x: 1, y: 0, z: 0))
        .animation(.easeOut(duration: 0.08), value: upPressed || downPressed)
    }

    private func half(_ symbol: String, _ b: RemoteSimulator.Button, pressed: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
            Text(b.keyLabel).imprint()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pressed ? Color.black.opacity(0.35) : .clear)
        .contentShape(Rectangle())
        .pressable(b, sim)
    }
}

private struct SideButton: View {
    let pressed: Bool

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .leading, endPoint: .trailing))
            .overlay(Image(systemName: "mic.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.7)))
            .frame(width: 8, height: 50)
            .offset(x: pressed ? -2 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// The touch-sensitive clickpad. Tap the ring for a direction or the centre to select; hold to
/// keep a direction pressed (it auto-repeats); drag to swipe.
private struct Clickpad: View {
    @EnvironmentObject var sim: RemoteSimulator
    @State private var finger: CGPoint?
    @State private var mode = Mode.idle
    @State private var anchor = CGPoint.zero
    @State private var holdTask: Task<Void, Never>?

    private enum Mode { case idle, pending(RemoteSimulator.Button), holding(RemoteSimulator.Button), swiping }

    private let size: CGFloat = 124
    /// Drag distance per swipe step, roughly the hardware's 30% of the surface.
    private var step: CGFloat { size * 0.24 }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.13), Color(white: 0.05)], center: .center,
                                     startRadius: 0, endRadius: size / 2))
                .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1).padding(1))
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            // The inner area that clicks as Select.
            Circle()
                .strokeBorder(.white.opacity(sim.pressed.contains(.select) ? 0.25 : 0.06), lineWidth: 1)
                .background(Circle().fill(.white.opacity(sim.pressed.contains(.select) ? 0.08 : 0)))
                .frame(width: size * 0.5, height: size * 0.5)
            Text(RemoteSimulator.Button.select.keyLabel).imprint()

            ForEach([RemoteSimulator.Button.up, .down, .left, .right], id: \.self) { b in
                ringMark(b)
            }

            if let finger {
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 22, height: 22)
                    .blur(radius: 2)
                    .position(finger)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isClicked ? 0.985 : 1)
        .animation(.easeOut(duration: 0.08), value: isClicked)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(changed)
                .onEnded { _ in ended() }
        )
    }

    private var isClicked: Bool {
        [RemoteSimulator.Button.up, .down, .left, .right, .select].contains { sim.pressed.contains($0) }
    }

    private func ringMark(_ b: RemoteSimulator.Button) -> some View {
        let r = size / 2 - 13
        let offset: CGSize = switch b {
        case .up: CGSize(width: 0, height: -r)
        case .down: CGSize(width: 0, height: r)
        case .left: CGSize(width: -r, height: 0)
        default: CGSize(width: r, height: 0)
        }
        let on = sim.pressed.contains(b)
        return ZStack {
            Circle().fill(.white.opacity(on ? 0.16 : 0)).frame(width: 30, height: 30).blur(radius: 4)
            Text(b.keyLabel).imprint().opacity(on ? 1 : 0.9)
        }
        .offset(offset)
    }

    private func region(at p: CGPoint) -> RemoteSimulator.Button {
        let dx = p.x - size / 2, dy = p.y - size / 2
        if hypot(dx, dy) < size * 0.25 { return .select }
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    private func changed(_ v: DragGesture.Value) {
        finger = v.location
        switch mode {
        case .idle:
            let b = region(at: v.startLocation)
            mode = .pending(b)
            anchor = v.startLocation
            // Held still: a long click, which auto-repeats for directions.
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, case .pending(b) = mode else { return }
                mode = .holding(b)
                sim.down(b)
            }
        case .pending:
            if hypot(v.location.x - anchor.x, v.location.y - anchor.y) > 6 {
                holdTask?.cancel()
                mode = .swiping
                swipe(v.location)
            }
        case .holding:
            break
        case .swiping:
            swipe(v.location)
        }
    }

    private func swipe(_ p: CGPoint) {
        let dx = p.x - anchor.x, dy = p.y - anchor.y
        if abs(dx) >= step, abs(dx) >= abs(dy) {
            sim.swipe(dx > 0 ? .right : .left)
            anchor.x += dx > 0 ? step : -step
            anchor.y = p.y
        } else if abs(dy) >= step {
            sim.swipe(dy > 0 ? .down : .up)
            anchor.y += dy > 0 ? step : -step
            anchor.x = p.x
        }
    }

    private func ended() {
        holdTask?.cancel()
        switch mode {
        case let .pending(b): sim.tap(b)
        case let .holding(b): sim.up(b)
        default: break
        }
        mode = .idle
        withAnimation(.easeOut(duration: 0.15)) { finger = nil }
    }
}

private extension View {
    /// Mouse down/up on a button, so holds (TV) and auto-repeat work like the hardware.
    func pressable(_ b: RemoteSimulator.Button, _ sim: RemoteSimulator) -> some View {
        gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in sim.down(b) }
                .onEnded { _ in sim.up(b) }
        )
    }
}

private extension Text {
    /// The tiny keybind printed on a button.
    func imprint(onDark: Bool = true) -> some View {
        font(.system(size: 7.5, weight: .semibold, design: .rounded))
            .foregroundStyle(onDark ? Color.white.opacity(0.42) : Color.black.opacity(0.35))
    }
}
