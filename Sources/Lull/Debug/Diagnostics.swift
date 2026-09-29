import Foundation
import SiriRemote

/// What the debug overlay shows: an event log, what each page reports about itself (DRM, codecs,
/// HDR...) and the remote's state. Anything can write to it; only the overlay reads it.
@MainActor
final class Diagnostics: ObservableObject {
    @Published var isVisible: Bool
    @Published private(set) var events: [String] = []
    /// Per service id, then report name.
    @Published private(set) var reports: [String: [String: String]] = [:]
    @Published var remote = SiriRemote.Status()

    private let echo: Bool
    private let maxEvents = 50

    init(visible: Bool, echoToStdout: Bool) {
        isVisible = visible
        echo = echoToStdout
    }

    func log(_ message: String) {
        let line = "\(Date().formatted(.dateTime.hour().minute().second())) \(message)"
        events.append(line)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        if echo { print(line); fflush(stdout) }
    }

    /// A fact a page reported. Live video stats arrive constantly, so they're kept out of the log.
    func report(_ id: String, _ key: String, _ value: String) {
        reports[id, default: [:]][key] = value
        if key != "video" { log("\(id) · \(key): \(value)") } else if echo { print("\(id) · video: \(value)") }
    }

    func toggle() { isVisible.toggle() }
}
