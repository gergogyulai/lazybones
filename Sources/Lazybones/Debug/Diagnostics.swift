import Foundation
import os
import SiriRemote

/// What the debug tools show: an event log, what each page reports about itself (DRM, codecs,
/// HDR...) and the remote's state. Anything can write to it; the overlay and the debug window read it.
///
/// Every entry also goes to the unified log under `Log.subsystem`, so `Scripts/logs.sh` (or
/// Console.app) sees it whether or not the app was started with `--log`.
@MainActor
final class Diagnostics: ObservableObject {
    @Published var isVisible: Bool
    @Published private(set) var events: [LogEntry] = []
    /// Per service id, then report name.
    @Published private(set) var reports: [String: [String: String]] = [:]
    /// Per service id: how many console errors and warnings its page has logged since it loaded.
    @Published private(set) var consoleCounts: [String: (errors: Int, warnings: Int)] = [:]
    @Published var remote = SiriRemote.Status()

    private let echo: Bool
    private let maxEvents: Int
    private var nextID = 0

    init(visible: Bool, echoToStdout: Bool, maxEvents: Int = 2000) {
        isVisible = visible
        echo = echoToStdout
        self.maxEvents = maxEvents
    }

    func log(_ message: String, _ category: LogCategory = .app, level: LogLevel = .info) {
        let entry = LogEntry(id: nextID, date: Date(), category: category, level: level, message: message)
        nextID += 1
        events.append(entry)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        Log.write(entry)
        if echo { print(entry.line); fflush(stdout) }
    }

    /// A fact a page reported. Live video stats arrive constantly, so they're kept out of the log.
    func report(_ id: String, _ key: String, _ value: String) {
        reports[id, default: [:]][key] = value
        if key == "video" {
            Log.logger(.web).debug("\(id, privacy: .public) · video: \(value, privacy: .public)")
            return
        }
        let failed = key == "video error" || value.hasPrefix("failed")
        log("\(id) · \(key): \(value)", .web, level: failed ? .error : .info)
    }

    /// Something a page wrote to its console (warnings and errors, or everything with `--page-log`).
    func console(_ id: String, _ level: LogLevel, _ message: String) {
        var counts = consoleCounts[id] ?? (0, 0)
        if level == .error { counts.errors += 1 } else if level == .warning { counts.warnings += 1 }
        consoleCounts[id] = counts
        log("\(id) · \(message)", .page, level: level)
    }

    /// A page started over: its console counts start over too.
    func pageReset(_ id: String) { consoleCounts[id] = nil }

    func clear() { events.removeAll() }

    func toggle() { isVisible.toggle() }
}

enum LogCategory: String, CaseIterable, Sendable {
    /// Opening, closing and quitting apps; settings; modes.
    case app
    /// Remote input, real and simulated.
    case remote
    /// Page loads and what pages report about themselves.
    case web
    /// What pages write to their consoles.
    case page
    case tv
    /// The ad blocker.
    case ext
    case audio
    /// Commands from `Scripts/ctl.sh`.
    case control
}

enum LogLevel: Int, Comparable, CaseIterable, Sendable {
    case debug, info, warning, error

    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .warning: "warn"
        case .error: "error"
        }
    }
}

struct LogEntry: Identifiable, Equatable, Sendable {
    let id: Int
    let date: Date
    let category: LogCategory
    let level: LogLevel
    let message: String

    var time: String { Self.timeFormat.string(from: date) }

    /// One line for a terminal or the clipboard.
    var line: String {
        let tag = level >= .warning ? " \(level.label.uppercased())" : ""
        return "\(time) \(category.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0))\(tag) \(message)"
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// The unified log, for what has no `Diagnostics` to hand (and as the sink for what does).
///
///     log stream --level debug --predicate 'subsystem == "dev.lull.lazybones"'
enum Log {
    static let subsystem = "dev.lull.lazybones"

    static func logger(_ category: LogCategory) -> Logger { Logger(subsystem: subsystem, category: category.rawValue) }

    static func write(_ entry: LogEntry) {
        let l = logger(entry.category)
        switch entry.level {
        case .debug: l.debug("\(entry.message, privacy: .public)")
        case .info: l.info("\(entry.message, privacy: .public)")
        case .warning: l.warning("\(entry.message, privacy: .public)")
        case .error: l.error("\(entry.message, privacy: .public)")
        }
    }

    /// For code with no `Diagnostics`: the unified log only.
    static func error(_ message: String, _ category: LogCategory = .app) {
        logger(category).error("\(message, privacy: .public)")
    }
}
