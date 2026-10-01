import Foundation
import SwiftUI

/// Volume button presses: applies them through the `VolumeRouter` and shows the volume HUD.
@MainActor
final class VolumeController: ObservableObject {
    enum Step { case up, down, toggleMute }

    /// Non-nil while the HUD is on screen.
    @Published private(set) var hud: VolumeState?

    let router: VolumeRouter
    private var hideTask: Task<Void, Never>?

    /// Percent per button press on the Mac; TVs step by 1 regardless.
    static let stepPercent = 6

    init(router: VolumeRouter) {
        self.router = router
    }

    /// Applies `step`. When `systemMayAct` is true and macOS handles the current output's volume
    /// itself (because the remote's buttons aren't exclusive), it has already acted, and Lazybones only
    /// shows the HUD. For the TV or app volume Lazybones always has to do it.
    func apply(_ step: Step, systemMayAct: Bool) {
        let systemActs = systemMayAct && router.systemHandlesVolume
        if !systemActs {
            switch step {
            case .up: router.change(by: Self.stepPercent)
            case .down: router.change(by: -Self.stepPercent)
            case .toggleMute: router.toggleMute()
            }
        }
        showHUD(after: systemActs ? .milliseconds(150) : .zero)
    }

    /// Keeps a visible HUD current when the TV reports a change.
    func refreshHUD() {
        if hud != nil, let state = router.state() { hud = state }
    }

    private func showHUD(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let state = router.state() else { return }
            withAnimation(Motion.present) { hud = state }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.dismiss) { hud = nil }
        }
    }
}
