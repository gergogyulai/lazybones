import AppKit
import SwiftUI

/// The simulator's window: floats above everything, including Lazybones in full screen (unless Keep
/// on Top is off), and turns keys into button presses and scrolling into swipes.
final class RemotePanel: NSPanel, NSWindowDelegate {
    static let frameName = "RemoteSimulatorWindow"
    private weak var simulator: RemoteSimulator?
    private var onTop: NSKeyValueObservation?

    init(simulator: RemoteSimulator, contentSize: NSSize) {
        self.simulator = simulator
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Siri Remote"
        // The content draws the title bar (`RemoteWindowContent.titleBar`); an empty unified toolbar
        // only makes the bar tall, with the traffic lights centred on it.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        toolbar = NSToolbar()
        toolbarStyle = .unified
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        delegate = self
        // Floats above everything (Lazybones in full screen included) unless asked not to.
        UserDefaults.standard.register(defaults: [RemoteSimulator.Preference.keepsOnTop: true])
        onTop = UserDefaults.standard.observe(\.remoteKeepsOnTop, options: [.initial, .new]) { [weak self] defaults, _ in
            let floats = defaults.remoteKeepsOnTop
            DispatchQueue.main.async { self?.level = floats ? .floating : .normal }
        }
    }

    override var canBecomeKey: Bool { true }

    // Caught before the views get them, so scrolling anywhere on the remote swipes.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel {
            MainActor.assumeIsolated { simulator?.scroll(event) }
            return
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        // ⇧ arrows swipe, and keep swiping while held, like a long drag.
        if event.modifierFlags.contains(.shift), let b = button(for: event), b.command.isDirection {
            return MainActor.assumeIsolated { simulator?.swipe(b.command) }
        }
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

private extension UserDefaults {
    /// For observing; the key is `RemoteSimulator.Preference.keepsOnTop`.
    @objc dynamic var remoteKeepsOnTop: Bool { bool(forKey: "remoteKeepsOnTop") }
}
