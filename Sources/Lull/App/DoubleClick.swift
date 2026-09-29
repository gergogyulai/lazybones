import Foundation

/// Recognizes a double click as the second of two clicks within `interval`. Nothing waits for the
/// second click: the first one acts at once, like the TV button on an Apple TV, which goes home
/// and then shows the app switcher if it is clicked again straight away.
struct DoubleClick {
    var interval: TimeInterval = 0.4
    private var last: TimeInterval?

    /// Registers a click, returning whether it completed a double click.
    mutating func click(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        if let last, now - last <= interval {
            self.last = nil
            return true
        }
        last = now
        return false
    }

    /// Forgets the last click, e.g. because it closed something rather than started a double click.
    mutating func reset() { last = nil }
}
