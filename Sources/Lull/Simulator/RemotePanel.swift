import AppKit
import SwiftUI

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
