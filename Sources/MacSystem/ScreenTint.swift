import AppKit
import CoreGraphics

/// Dims the displays and filters blue light by scaling their gamma tables, the way Night Shift and
/// f.lux do. Unlike an overlay it covers everything on screen, video included, and black stays
/// black. macOS puts the tables back when the process exits; `restore()` does it sooner.
@MainActor
public final class ScreenTint {
    public struct Level: Equatable, Sendable {
        /// How far to dim: 0 leaves brightness alone, 1 is as dark as the tables allow.
        public var dim: Double
        /// How much blue to filter out: 0 is none, 1 is candlelight.
        public var warmth: Double

        public static let off = Level(dim: 0, warmth: 0)

        /// Never darker than this, so the screen can always be found again.
        static let floor = 0.12

        public init(dim: Double, warmth: Double) {
            self.dim = min(max(dim, 0), 1)
            self.warmth = min(max(warmth, 0), 1)
        }

        /// Peak output per channel, 0...1. Blue is cut hardest and green a little, which is what
        /// shifts white toward amber.
        public var gains: (red: Float, green: Float, blue: Float) {
            let brightness = 1 - dim * (1 - Self.floor)
            return (Float(brightness),
                    Float(brightness * (1 - 0.32 * warmth)),
                    Float(brightness * (1 - 0.65 * warmth)))
        }

        func blended(to other: Level, _ t: Double) -> Level {
            Level(dim: dim + (other.dim - dim) * t, warmth: warmth + (other.warmth - warmth) * t)
        }
    }

    public private(set) var level = Level.off

    private var ramp: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    public init() {
        // Sleeping, waking and changing screens can all reset the tables.
        let center = NotificationCenter.default
        let reapply: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.write(self?.level ?? .off) }
        }
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main, using: reapply))
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main, using: reapply))
        }
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restore() }
        })
    }

    /// Moves to `target`, easing there so switching on doesn't jolt the eyes.
    public func set(_ target: Level, animated: Bool = true) {
        ramp?.cancel()
        guard animated, target != level else {
            level = target
            write(target)
            return
        }
        let start = level
        let steps = 24
        ramp = Task { [weak self] in
            for i in 1...steps {
                guard let self, !Task.isCancelled else { return }
                let t = Double(i) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                level = start.blended(to: target, eased)
                write(level)
                try? await Task.sleep(for: .milliseconds(30))
            }
            self?.level = target
            self?.write(target)
        }
    }

    /// Back to the display profile right now.
    public func restore() {
        ramp?.cancel()
        level = .off
        CGDisplayRestoreColorSyncSettings()
    }

    private func write(_ l: Level) {
        guard l != .off else { return CGDisplayRestoreColorSyncSettings() }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return }
        let g = l.gains
        for id in ids.prefix(Int(count)) {
            CGSetDisplayTransferByFormula(id, 0, g.red, 1, 0, g.green, 1, 0, g.blue, 1)
        }
    }
}
