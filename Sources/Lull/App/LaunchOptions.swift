import Foundation

/// Command-line switches, parsed once. Mostly for development:
///
///     Lull.app/Contents/MacOS/Lull --log --open youtube --remote
struct LaunchOptions: Equatable {
    /// Don't go full screen, whatever the setting says.
    var windowed = false
    /// Echo the event log to stdout.
    var log = false
    /// Don't load the ad blocker.
    var noExtensions = false
    /// Show the on-screen remote at launch.
    var remote = false
    /// Report the ad blocker's rulesets once it has loaded.
    var extensionDebug = false
    /// Open this service (by id) at launch.
    var open: String?
    /// Seconds to wait after the ad blocker has loaded before opening `open`.
    var openDelay: Double?

    static let current = LaunchOptions(arguments: Array(CommandLine.arguments.dropFirst()))

    static let usage = """
    --windowed        don't start in full screen
    --log             echo the event log to stdout
    --no-ext          don't load the ad blocker
    --remote          show the on-screen remote
    --ext-debug       report the ad blocker's rulesets
    --open <id>       open a service at launch (e.g. youtube)
    --open-delay <s>  wait this long (after the ad blocker loads, if it's on) before opening
    """

    init() {}

    init(arguments: [String]) {
        var args = arguments[...]
        while let arg = args.popFirst() {
            switch arg {
            case "--windowed": windowed = true
            case "--log": log = true
            case "--no-ext": noExtensions = true
            case "--remote": remote = true
            case "--ext-debug": extensionDebug = true
            case "--open": open = args.popFirst()
            case "--open-delay": openDelay = args.popFirst().flatMap(Double.init)
            default: break
            }
        }
    }
}
