import Foundation

/// Command-line switches, parsed once. Mostly for development:
///
///     Lazybones.app/Contents/MacOS/Lazybones --log --open youtube --remote
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
    /// Show the debug overlay at launch, whatever the setting says.
    var debug = false
    /// Forward everything pages log to the event log, not just their warnings and errors.
    var pageLog = false
    /// Take commands from `Scripts/ctl.sh`. Always on in debug builds.
    var control = false
    /// Start from default settings, kept apart from (and without touching) the real ones.
    var freshSettings = false
    /// Leave the Siri Remote (and the iPhone's) alone, e.g. for a second instance next to one that's using it.
    var noHardwareRemote = false
    /// Log the iPhone remote's whole conversation.
    var phoneDebug = false

    /// Whether `Scripts/ctl.sh` can drive the app.
    var acceptsControl: Bool {
        #if DEBUG
        true
        #else
        control
        #endif
    }

    static let current = LaunchOptions(arguments: Array(CommandLine.arguments.dropFirst()))

    static let usage = """
    --windowed        don't start in full screen
    --log             echo the event log to stdout
    --no-ext          don't load the ad blocker
    --remote          show the on-screen remote
    --ext-debug       report the ad blocker's rulesets
    --open <id>       open a service at launch (e.g. youtube)
    --open-delay <s>  wait this long (after the ad blocker loads, if it's on) before opening
    --debug           show the debug overlay
    --page-log        forward everything pages log, not just warnings and errors
    --control         take commands from Scripts/ctl.sh (always on in debug builds)
    --fresh-settings  start from default settings, without touching the saved ones
    --no-hw-remote    leave the Siri Remote and the iPhone to another instance (the on-screen one still works)
    --phone-debug     log every message the iPhone remote sends, not just connections and pairing
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
            case "--debug": debug = true
            case "--page-log": pageLog = true
            case "--control": control = true
            case "--fresh-settings": freshSettings = true
            case "--no-hw-remote": noHardwareRemote = true
            case "--phone-debug": phoneDebug = true
            default: break
            }
        }
    }
}
