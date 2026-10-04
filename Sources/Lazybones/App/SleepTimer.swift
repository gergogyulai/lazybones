import Foundation

/// Stops playback and turns the screen off after a set time, like the TV's own sleep timer. Set
/// from Control Center: left and right step through `presets`, a click turns it on or off.
@MainActor
final class SleepTimer: ObservableObject {
    /// The lengths it steps through, in minutes.
    static let presets = [15, 30, 45, 60, 90, 120]
    /// What a click turns it on to, before any length has been picked.
    static let defaultMinutes = 30

    /// When it goes off, or nil while it's off.
    @Published private(set) var endsAt: Date?
    /// The preset it was last set to, which a click turns it back on to.
    @Published private(set) var minutes = SleepTimer.defaultMinutes

    /// Called when it goes off.
    var onFire: (() -> Void)?

    private var task: Task<Void, Never>?

    var isOn: Bool { endsAt != nil }

    func toggle() {
        if isOn { cancel() } else { start(minutes) }
    }

    /// Right from off starts at the shortest length; left from the shortest turns it off. Each step
    /// starts the countdown again from the new length.
    func step(_ direction: Int) {
        let i = isOn ? Self.presets.firstIndex(of: minutes) ?? 0 : -1
        let next = min(i + direction, Self.presets.count - 1)
        if next < 0 { cancel() } else { start(Self.presets[next]) }
    }

    func start(_ minutes: Int) {
        self.minutes = minutes
        schedule(after: TimeInterval(minutes * 60))
    }

    func cancel() {
        task?.cancel()
        task = nil
        endsAt = nil
    }

    /// Separate from `start` so tests can use a short delay.
    func schedule(after seconds: TimeInterval) {
        task?.cancel()
        endsAt = Date(timeIntervalSinceNow: seconds)
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.task = nil
            self.endsAt = nil
            self.onFire?()
        }
    }

    /// "29 min left", rounded up so it never reads 0 while running.
    static func label(remaining: TimeInterval) -> String {
        remaining < 60 ? "Less than a minute" : "\(Int((remaining / 60).rounded(.up))) min left"
    }
}
