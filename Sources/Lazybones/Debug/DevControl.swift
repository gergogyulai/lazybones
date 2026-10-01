import Foundation
import SiriRemote

/// A command from `Scripts/ctl.sh`, for driving the app from a terminal (or a script, or an agent)
/// without the remote: pressing buttons, opening apps, running JavaScript in a page, reading state.
enum DevCommand: Equatable {
    /// Buttons pressed one after another (or one held).
    case press([RemoteCommand], hold: Bool)
    /// Swipes on the touch surface, one after another; only directions.
    case swipe([RemoteCommand])
    case open(String)
    /// JavaScript to run in a service's page; the open one if no id is given.
    case eval(String, in: String?)
    case state
    case log(lines: Int)
    case settings
    case reload
    case overlay
    case window

    static let usage = """
    press <button>... [hold] up down left right select back home playpause volup voldown mute siri power
    swipe <direction>...    swipe on the touch surface (up down left right)
    open <id>               open a service (youtube, netflix...)
    eval [@<id>] <js>       run JavaScript in the open page (or <id>'s) and print the result
    state                   what the app is showing and doing
    log [n]                 the last n log lines (default 50)
    settings                the saved settings, as JSON
    reload                  reload the open page
    overlay                 toggle the debug overlay
    window                  open the debug window
    """

    static let buttons: [String: RemoteCommand] = [
        "up": .up, "down": .down, "left": .left, "right": .right, "select": .select, "ok": .select,
        "back": .back, "menu": .back, "home": .home, "tv": .home, "playpause": .playPause, "play": .playPause,
        "volup": .volumeUp, "voldown": .volumeDown, "mute": .mute, "siri": .siri, "power": .power,
    ]

    /// Parses `ctl.sh`'s arguments. Nil for anything it doesn't know.
    init?(_ args: [String]) {
        guard let name = args.first?.lowercased() else { return nil }
        let rest = Array(args.dropFirst())
        switch name {
        case "press":
            let hold = rest.last == "hold"
            let names = hold ? rest.dropLast() : rest[...]
            let buttons = names.compactMap { Self.buttons[$0.lowercased()] }
            guard !buttons.isEmpty, buttons.count == names.count, !hold || buttons.count == 1 else { return nil }
            self = .press(buttons, hold: hold)
        case "swipe":
            let directions = rest.compactMap { Self.buttons[$0.lowercased()] }
            guard !directions.isEmpty, directions.count == rest.count, directions.allSatisfy(\.isDirection) else { return nil }
            self = .swipe(directions)
        case "open":
            guard let id = rest.first else { return nil }
            self = .open(id)
        case "eval":
            var words = rest[...]
            var id: String?
            if let first = words.first, first.hasPrefix("@") {
                id = String(first.dropFirst())
                words = words.dropFirst()
            }
            guard !words.isEmpty else { return nil }
            self = .eval(words.joined(separator: " "), in: id)
        case "state": self = .state
        case "log": self = .log(lines: rest.first.flatMap(Int.init) ?? 50)
        case "settings": self = .settings
        case "reload": self = .reload
        case "overlay", "debug": self = .overlay
        case "window": self = .window
        default: return nil
        }
    }
}

/// Listens for `DevCommand`s, which `Scripts/ctl.sh` posts as distributed notifications, and writes
/// each reply to the file the command names. Only another process run by the same user can post
/// these, and the app only listens with `--control` or in a debug build.
///
/// The name carries the process id, so with two instances running (a dev build next to the one in
/// use) a command reaches only the one it was meant for.
@MainActor
final class DevControl {
    static let notification = Notification.Name("dev.lull.lazybones.control.\(ProcessInfo.processInfo.processIdentifier)")

    private var observer: NSObjectProtocol?

    init(run: @escaping @MainActor (DevCommand) async -> String) {
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.notification, object: nil,
                                                                       queue: .main) { note in
            let info = note.userInfo ?? [:]
            let args = info["args"] as? [String] ?? []
            let reply = (info["reply"] as? String).map(URL.init(fileURLWithPath:))
            Task { @MainActor in
                let text = if let command = DevCommand(args) {
                    await run(command)
                } else {
                    "error: unknown command \(args.joined(separator: " "))\n\n\(DevCommand.usage)"
                }
                if let reply { try? Data(text.utf8).write(to: reply, options: .atomic) }
            }
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
