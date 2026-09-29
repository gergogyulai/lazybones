import AppKit
import LGTV
import MacSystem
import SiriRemote
import SwiftUI

/// Coordinates the app: decides what a remote command means right now (launcher, Control Center,
/// on-screen keyboard or the open service) and reacts to settings changes. The parts it
/// coordinates each own their own state and know nothing about each other.
@MainActor
final class AppModel: ObservableObject {
    @Published var selected = 0
    @Published var active: Service?
    @Published var settings: LauncherSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    /// Bumped to ask the UI to open the Settings window (only views can do that).
    @Published private(set) var settingsRequests = 0

    let remote = SiriRemote()
    let tv = TVLink()
    let web = WebPool()
    let extensions = Extensions()
    let keyboard = KeyboardController()
    let diagnostics: Diagnostics
    let volume: VolumeController
    let controlCenter: ControlCenter
    private(set) lazy var simulator = RemoteSimulator { [unowned self] in handle($0, simulated: true) }

    var columns: Int { settings.columns }
    var visible: [Service] { settings.visibleServices }

    private let options: LaunchOptions
    private let store = SettingsStore()
    private var keyboardBridge: KeyboardBridge?
    private var keyMonitor: Any?
    private var lastTVStatus = TVLink.Status.off

    init(options: LaunchOptions = .current) {
        let settings = store.load()
        let diagnostics = Diagnostics(visible: settings.showDebugOnLaunch, echoToStdout: options.log)
        let router = VolumeRouter(tv: tv) { [web] level, muted in web.setMediaVolume(level, muted: muted) }
        router.usesTV = settings.tvVolume

        self.options = options
        self.settings = settings
        self.diagnostics = diagnostics
        self.volume = VolumeController(router: router)
        self.controlCenter = ControlCenter(audio: router, tv: tv)

        keyboardBridge = KeyboardBridge(keyboard: keyboard, web: web,
                                        activeService: { [weak self] in self?.active },
                                        isEnabled: { [weak self] in self?.settings.keyboard ?? false })
        wireUp()
        applySettings()
        launch()
    }

    // MARK: Setup

    private func wireUp() {
        remote.onEvent = { [weak self] in self?.handle($0) }
        remote.onDiagnostic = { [weak self] in self?.diagnostics.log("remote: \($0)") }
        remote.onStatusChange = { [weak self] status in
            guard let self else { return }
            let old = diagnostics.remote
            diagnostics.remote = status
            if status.buttons != old.buttons || status.touch != old.touch {
                diagnostics.log("remote: buttons \(status.buttons), touch \(status.touch ? "connected" : "not found")")
            }
        }

        tv.onPaired = { [weak self] key in self?.settings.tv?.clientKey = key }
        tv.onChange = { [weak self] in
            guard let self else { return }
            if tv.status != lastTVStatus {
                lastTVStatus = tv.status
                diagnostics.log("tv \(tv.name): \(tv.status)")
            }
            volume.refreshHUD()
            if controlCenter.isOpen { controlCenter.volume = volume.router.state() }
        }

        web.onReport = { [weak self] id, key, value in self?.diagnostics.report(id, key, value) }

        // Keyboard fallback for the launcher; inside a service the page gets keys directly.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            MainActor.assumeIsolated { self?.launcherKey(ev) ?? false } ? nil : ev
        }
    }

    private func applySettings() {
        tv.configure(settings.tv)
        keyboard.layout = settings.keyboardLayout
        volume.router.usesTV = settings.tvVolume
    }

    private func launch() {
        let initial = options.open.flatMap { id in settings.services.first { $0.id == id } }
        if options.noExtensions {
            if let initial { open(initial) }
        } else {
            web.extensions = extensions
            extensions.onStatus = { [weak self] in self?.diagnostics.log($0) }
            Task {
                await extensions.loadBundled(inspect: options.extensionDebug)
                if let secs = options.openDelay { try? await Task.sleep(for: .seconds(secs)) }
                if let initial { open(initial) }
            }
        }
        remote.start()
        if options.remote { DispatchQueue.main.async { self.simulator.show() } }
    }

    /// Whether to go full screen at launch.
    var startsFullScreen: Bool { settings.startFullScreen && !options.windowed }

    // MARK: Remote

    /// `simulated` events come from the on-screen remote, which macOS never acts on itself.
    func handle(_ event: RemoteEvent, simulated: Bool = false) {
        diagnostics.log("\(simulated ? "sim " : "")\(event.source) \(event.command)")
        if (event.command == .home && event.source == .hold) || event.command == .power {
            toggleControlCenter()
            return
        }
        if controlCenter.isOpen {
            switch event.command {
            case .home:
                perform(.home)
                return
            case _ where event.command.isDirection, .select, .back, .playPause:
                if let action = controlCenter.handle(event.command) { perform(action) }
                return
            default: break
            }
        }
        if event.command != .home, keyboard.handle(event.command) { return }
        switch event.command {
        case .home: goHome()
        case .siri: diagnostics.toggle()
        case .volumeUp: changeVolume(.up, simulated: simulated)
        case .volumeDown: changeVolume(.down, simulated: simulated)
        case .mute: changeVolume(.toggleMute, simulated: simulated)
        default:
            if let s = active { web.send(event.command, to: s) } else { navigate(event.command) }
        }
    }

    private func changeVolume(_ step: VolumeController.Step, simulated: Bool) {
        // Unless the remote's buttons are exclusive, macOS acts on volume keys itself.
        volume.apply(step, systemMayAct: !simulated && diagnostics.remote.buttons != .exclusive)
    }

    private func navigate(_ command: RemoteCommand) {
        let n = visible.count
        guard n > 0 else { return }
        switch command {
        case .left: selected = max(0, selected - 1)
        case .right: selected = min(n - 1, selected + 1)
        case .up: if selected >= columns { selected -= columns }
        case .down: selected = min(n - 1, selected + columns)
        case .select: open(visible[selected])
        default: break
        }
    }

    private func launcherKey(_ ev: NSEvent) -> Bool {
        // The simulator window turns keys into remote presses itself.
        guard !(ev.window is RemotePanel), active == nil || controlCenter.isOpen,
              ev.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad]).isEmpty
        else { return false }
        let map: [UInt16: RemoteCommand] = [123: .left, 124: .right, 125: .down, 126: .up, 36: .select, 53: .back]
        guard let command = map[ev.keyCode] else { return false }
        if controlCenter.isOpen {
            if let action = controlCenter.handle(command) { perform(action) }
        } else {
            navigate(command)
        }
        return true
    }

    // MARK: Services

    func open(_ s: Service) {
        extensions.activate(web.view(for: s))
        active = s
        diagnostics.log("open \(s.name)")
    }

    func goHome() {
        guard let s = active else { return }
        keyboard.dismiss()
        web.pause(s)
        active = nil
    }

    func reload() {
        if let s = active { web.reload(s) }
    }

    // MARK: Control Center

    func toggleControlCenter() {
        if controlCenter.isOpen { controlCenter.close() } else { controlCenter.open(canReload: active != nil) }
    }

    func perform(_ action: ControlCenter.Action) {
        controlCenter.close()
        switch action {
        case .close: break
        case .home: goHome()
        case .reload: reload()
        case .toggleDebug: diagnostics.toggle()
        case .settings: settingsRequests += 1
        case .tvOff: tv.turnOff()
        case .sleep: SystemSleep.displays()
        }
    }

    // MARK: Settings

    private func settingsChanged(from old: LauncherSettings) {
        store.save(settings)
        applySettings()
        if !settings.keyboard { keyboard.hide() }
        // A service whose page settings changed gets a fresh web view next time it opens.
        for s in settings.services {
            guard let before = old.services.first(where: { $0.id == s.id }),
                  before.url != s.url || before.agent != s.agent || before.spatialNav != s.spatialNav else { continue }
            discard(s.id)
        }
        for s in old.services where !settings.services.contains(where: { $0.id == s.id }) {
            discard(s.id)
        }
        selected = min(selected, max(visible.count - 1, 0))
        if active == nil { keyboard.hide() }
    }

    private func discard(_ id: String) {
        if active?.id == id { active = nil }
        web.discard(id)
    }
}
