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

    func panelClosed() {
        releaseAll()
        isVisible = false
    }
}
