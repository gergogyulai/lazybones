import AppKit
import LGTV
import MacSystem
import SiriRemote
import SwiftUI

/// Coordinates the app: decides what a remote command means right now (launcher, Control Center,
/// app switcher, settings, on-screen keyboard or the open service) and reacts to settings changes.
/// The parts it coordinates each own their own state and know nothing about each other.
@MainActor
final class AppModel: ObservableObject {
    // MARK: Home Screen

    @Published private(set) var focus = GridFocus()
    /// Bumped on every attempt to move focus, even one that hits an edge, so the focused icon can
    /// tilt toward `navDirection` either way.
    @Published private(set) var navTick = 0
    @Published private(set) var navDirection = CGSize.zero
    /// Where the launcher sits in the window, so a service can zoom out of and back into its icon.
    var launcherFrame = CGRect.zero

    // MARK: Services

    /// The service the remote is driving: set the moment one opens, cleared the moment you go Home.
    @Published private(set) var active: Service?
    /// The service on screen, which outlasts `active` while it zooms back into its icon.
    @Published private(set) var presented: Service?
    /// Whether the presented service has zoomed out to fill the screen.
    @Published private(set) var zoomed = false
    /// Services whose first page hasn't loaded yet, which show a launch screen meanwhile.
    @Published private(set) var loading: Set<String> = []
    /// Services with media playing, per their pages.
    @Published private(set) var playing: Set<String> = []

    // MARK: Settings and modes

    @Published var settings: LauncherSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    @Published private(set) var sleepMode = false
    /// Bumped to ask the UI to open the Mac's Settings window (only views can do that).
    @Published private(set) var settingsRequests = 0
    /// The TV being paired from the settings screen, and how that went.
    @Published private(set) var tvPairing: String?
    @Published private(set) var tvPairError: String?

    let remote = SiriRemote()
    let tv = TVLink()
    let web = WebPool()
    let extensions = Extensions()
    let keyboard = KeyboardController()
    let switcher = AppSwitcher()
    let settingsScreen = SettingsScreen()
    let tint = ScreenTint()
    let diagnostics: Diagnostics
    let volume: VolumeController
    let controlCenter: ControlCenter
    private(set) lazy var simulator = RemoteSimulator { [unowned self] in handle($0, simulated: true) }

    var columns: Int { settings.columns }
    var visible: [Service] { settings.visibleServices }
    var selected: Int { focus.index }

    /// Services whose pages are mounted: the one on screen, and any playing on behind the Home Screen.
    var mounted: [Service] {
        settings.services.filter { s in
            web.views[s.id] != nil && (s.id == presented?.id || playsInBackground(s))
        }
    }

    /// Services making sound behind the Home Screen, which is why their pages stay mounted.
    var backgroundAudio: [Service] { settings.services.filter(playsInBackground) }

    private let options: LaunchOptions
    private let store: SettingsStore
    private let startsRemote: Bool
    private var keyboardBridge: KeyboardBridge?
    private var keyMonitor: Any?
    private var lastTVStatus = TVLink.Status.off
    private var homeClicks = DoubleClick()
    private var recents = Recents()
    /// Bumped for each open or close, so a finished animation can tell it has been overtaken.
    private var presentation = 0
    /// The music service Play/Pause controls from the Home Screen.
    private var audioServiceID: String?
    private var lastPointer = NSEvent.mouseLocation

    /// `store` and `startsRemote` are for tests, which mustn't touch the user's settings or the remote.
    init(options: LaunchOptions = .current, store: SettingsStore = SettingsStore(), startsRemote: Bool = true) {
        let settings = store.load()
        let diagnostics = Diagnostics(visible: settings.showDebugOnLaunch, echoToStdout: options.log)
        let router = VolumeRouter(tv: tv) { [web] level, muted in web.setMediaVolume(level, muted: muted) }
        router.usesTV = settings.tvVolume

        self.options = options
        self.store = store
        self.startsRemote = startsRemote
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

        web.onReport = { [weak self] id, key, value in
            self?.diagnostics.report(id, key, value)
            if key == "playing" { self?.setPlaying(id, value == "1") }
        }
        web.onLoaded = { [weak self] id in self?.loading.remove(id) }

        settingsScreen.rowsProvider = { [weak self] in self?.settingsRows(for: $0) ?? [] }

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
        if !options.noExtensions {
            web.extensions = extensions
            extensions.onStatus = { [weak self] in self?.diagnostics.log($0) }
        }
        Task {
            if !options.noExtensions { await extensions.loadBundled(inspect: options.extensionDebug) }
            if let secs = options.openDelay { try? await Task.sleep(for: .seconds(secs)) }
            if let initial { open(initial) }
        }
        if startsRemote { remote.start() }
        if options.remote { DispatchQueue.main.async { self.simulator.show() } }
    }

    /// Whether to go full screen at launch.
    var startsFullScreen: Bool { settings.startFullScreen && !options.windowed }

    // MARK: Remote

    /// `simulated` events come from the on-screen remote, which macOS never acts on itself.
    func handle(_ event: RemoteEvent, simulated: Bool = false) {
        diagnostics.log("\(simulated ? "sim " : "")\(event.source) \(event.command)")
        let command = event.command
        if (command == .home && event.source == .hold) || command == .power {
            toggleControlCenter()
            return
        }
        if command == .home {
            homePressed()
            return
        }
        if overlayHandle(command) { return }
        if keyboard.handle(command) { return }
        switch command {
        case .siri: diagnostics.toggle()
        case .volumeUp: changeVolume(.up, simulated: simulated)
        case .volumeDown: changeVolume(.down, simulated: simulated)
        case .mute: changeVolume(.toggleMute, simulated: simulated)
        case .playPause:
            if let s = active { web.send(command, to: s) } else { toggleBackgroundAudio() }
        case .back:
            if let s = active { back(in: s) }
        default:
            if let s = active { web.send(command, to: s) } else { navigate(command, repeating: event.source == .repeat) }
        }
    }

    /// Control Center, the settings screen and the app switcher take navigation first. Returns
    /// whether one of them did.
    private func overlayHandle(_ command: RemoteCommand) -> Bool {
        let navigation = command.isDirection || command == .select || command == .back
        if controlCenter.isOpen {
            guard navigation || command == .playPause else { return false }
            if let action = controlCenter.handle(command) { perform(action) }
            return true
        }
        guard navigation else { return false }
        if settingsScreen.isOpen {
            settingsScreen.handle(command)
            return true
        }
        if switcher.isOpen {
            if let action = switcher.handle(command) { perform(action) }
            return true
        }
        return false
    }

    private var overlayOpen: Bool { controlCenter.isOpen || settingsScreen.isOpen || switcher.isOpen }

    private func changeVolume(_ step: VolumeController.Step, simulated: Bool) {
        // Unless the remote's buttons are exclusive, macOS acts on volume keys itself.
        volume.apply(step, systemMayAct: !simulated && diagnostics.remote.buttons != .exclusive)
    }

    // MARK: Home button

    /// A click of the TV button: Home, and on a second click straight after, the app switcher.
    func homePressed() {
        if switcher.isOpen {
            switcher.close()
            homeClicks.reset()
            return
        }
        let double = homeClicks.click()
        if controlCenter.isOpen { controlCenter.close() }
        if settingsScreen.isOpen { settingsScreen.close() }
        goHome()
        if double { openSwitcher() }
    }

    // MARK: Launcher

    private func navigate(_ command: RemoteCommand, repeating: Bool = false) {
        switch command {
        case .left, .right, .up, .down:
            let moved = focus.move(command, count: visible.count, columns: columns)
            // Holding a direction at an edge shouldn't keep nudging.
            guard moved || !repeating else { return }
            navDirection = switch command {
            case .left: CGSize(width: -1, height: 0)
            case .right: CGSize(width: 1, height: 0)
            case .up: CGSize(width: 0, height: -1)
            default: CGSize(width: 0, height: 1)
            }
            navTick += 1
        case .select:
            if focus.onBar {
                openSettingsScreen()
            } else if visible.indices.contains(focus.index) {
                open(visible[focus.index])
            }
        default: break
        }
    }

    /// The pointer came over an app. A pointer sitting still while the grid scrolls under it also
    /// reports that, so it only counts if the pointer really moved.
    func hover(app i: Int) {
        guard pointerMoved(), focus.onBar || focus.index != i else { return }
        focus.select(i, columns: columns)
    }

    func hoverBar() {
        guard pointerMoved(), !focus.onBar else { return }
        focus.selectBar()
    }

    private func pointerMoved() -> Bool {
        let p = NSEvent.mouseLocation
        defer { lastPointer = p }
        return p != lastPointer
    }

    /// A click on an app.
    func click(app i: Int) {
        guard visible.indices.contains(i) else { return }
        focus.select(i, columns: columns)
        open(visible[i])
    }

    private func launcherKey(_ ev: NSEvent) -> Bool {
        // The simulator window turns keys into remote presses itself.
        guard !(ev.window is RemotePanel), active == nil || overlayOpen,
              ev.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad]).isEmpty
        else { return false }
        let map: [UInt16: RemoteCommand] = [123: .left, 124: .right, 125: .down, 126: .up, 36: .select, 53: .back]
        guard let command = map[ev.keyCode] else { return false }
        if !overlayHandle(command) { navigate(command, repeating: ev.isARepeat) }
        return true
    }

    // MARK: Services

    func open(_ s: Service) {
        if active?.id == s.id { return }
        if let i = visible.firstIndex(where: { $0.id == s.id }) { focus.select(i, columns: columns) }
        if web.views[s.id] == nil { expectLoad(of: s.id) }
        extensions.activate(web.view(for: s))
        recents.touch(s.id)
        // Video takes over from music that was playing behind the Home Screen.
        if ServiceModules.module(for: s).pausesInBackground {
            for other in backgroundAudio where other.id != s.id { web.pause(other) }
        }

        presentation += 1
        let token = presentation
        active = s
        if presented?.id != s.id {
            presented = s
            zoomed = false
        }
        diagnostics.log("open \(s.name)")
        // Let the icon-sized first frame render before growing out of it.
        DispatchQueue.main.async { [self] in
            guard presentation == token else { return }
            withAnimation(Self.zoomIn) { zoomed = true }
        }
    }

    func goHome() {
        guard let s = active else {
            // Already Home: the TV button scrolls back to the first app.
            if presented == nil, focus != GridFocus() {
                focus.reset(columns: columns)
                navDirection = .zero
                navTick += 1
            }
            return
        }
        keyboard.dismiss()
        if ServiceModules.module(for: s).pausesInBackground { web.pause(s) }
        // While it's still on screen: what the app switcher will show.
        web.snapshot(s) { [weak self] in self?.switcher.setSnapshot($0, for: s.id) }
        active = nil

        // A page in its own full screen leaves it first, or the app would shrink out of sight
        // behind that window.
        web.leaveFullscreen(s) { [self] in
            guard active == nil, presented?.id == s.id else { return }
            web.views[s.id]?.window?.makeFirstResponder(nil)
            presentation += 1
            let token = presentation
            withAnimation(Self.zoomOut, completionCriteria: .logicallyComplete) {
                zoomed = false
            } completion: { [self] in
                if presentation == token { presented = nil }
            }
        }
    }

    func reload() {
        if let s = active { web.reload(s) }
    }

    /// Back in the open service: whatever the page does with it, else the page before, else Home.
    private func back(in s: Service) {
        web.back(from: s) { [weak self] handled in
            guard let self, !handled, active?.id == s.id else { return }
            goHome()
        }
    }

    private func expectLoad(of id: String) {
        loading.insert(id)
        // A page that never reports back shouldn't hide behind its launch screen forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.loading.remove(id)
        }
    }

    // MARK: Playback

    private func playsInBackground(_ s: Service) -> Bool {
        playing.contains(s.id) && !ServiceModules.module(for: s).pausesInBackground && web.views[s.id] != nil
    }

    private func setPlaying(_ id: String, _ on: Bool) {
        guard playing.contains(id) != on else { return }
        if on {
            playing.insert(id)
            if let s = settings.services.first(where: { $0.id == id }), !ServiceModules.module(for: s).pausesInBackground {
                audioServiceID = id
            }
        } else {
            playing.remove(id)
        }
    }

    /// Play/Pause on the Home Screen controls the music that was left playing.
    private func toggleBackgroundAudio() {
        guard let id = audioServiceID, let s = settings.services.first(where: { $0.id == id }) else { return }
        web.togglePlayback(s)
    }

    // MARK: App switcher

    func openSwitcher() {
        if controlCenter.isOpen { controlCenter.close() }
        if settingsScreen.isOpen { settingsScreen.close() }
        let apps = recents.ids.compactMap { id in settings.services.first { $0.id == id } }
            .filter { web.views[$0.id] != nil }
        switcher.open(apps)
    }

    func perform(_ action: AppSwitcher.Action) {
        switch action {
        case .dismiss: switcher.close()
        case let .resume(s):
            switcher.close()
            open(s)
        case let .quit(s):
            diagnostics.log("quit \(s.name)")
            discard(s.id)
        }
    }

    // MARK: Control Center

    func toggleControlCenter() {
        if controlCenter.isOpen {
            controlCenter.close()
        } else {
            controlCenter.open(canReload: active != nil, showsSleepMode: settings.sleepInControlCenter,
                               sleepModeOn: sleepMode)
        }
    }

    func perform(_ action: ControlCenter.Action) {
        // A toggle leaves Control Center open so you can see it flip.
        if case .toggleSleepMode = action {
            toggleSleepMode()
            return
        }
        controlCenter.close()
        switch action {
        case .close, .toggleSleepMode: break
        case .home: goHome()
        case .reload: reload()
        case .toggleDebug: diagnostics.toggle()
        case .settings: openSettingsScreen()
        case .tvOff: tv.turnOff()
        case .displayOff: SystemSleep.displays()
        case .quit: NSApp.terminate(nil)
        }
    }

    // MARK: Settings

    func openSettingsScreen(page: SettingsScreen.Page? = nil) {
        if controlCenter.isOpen { controlCenter.close() }
        if switcher.isOpen { switcher.close() }
        settingsScreen.open(page: page)
    }

    /// Opens the Mac's Settings window (⌘,).
    func openMacSettings() { settingsRequests += 1 }

    func setSleepMode(_ on: Bool) {
        guard on != sleepMode else { return }
        sleepMode = on
        controlCenter.sleepModeOn = on
        tint.set(on ? settings.sleepLevel : .off)
        diagnostics.log("sleep mode \(on ? "on" : "off")")
    }

    func toggleSleepMode() { setSleepMode(!sleepMode) }

    func pair(_ found: FoundTV) {
        guard tvPairing == nil else { return }
        tvPairing = found.name
        tvPairError = nil
        Task {
            let host = await TVDiscovery.resolve(found)
            tvPairing = nil
            if let host {
                settings.tv = TVConfig(name: found.name, host: host)
            } else {
                tvPairError = "Couldn't reach \(found.name). Check that it's on and on this network."
            }
        }
    }

    private func settingsChanged(from old: LauncherSettings) {
        store.save(settings)
        applySettings()
        if !settings.keyboard { keyboard.hide() }
        if sleepMode, old.sleepLevel != settings.sleepLevel { tint.set(settings.sleepLevel, animated: false) }
        // A service whose page settings changed gets a fresh web view next time it opens.
        for s in settings.services {
            guard let before = old.services.first(where: { $0.id == s.id }),
                  before.url != s.url || before.agent != s.agent || before.spatialNav != s.spatialNav else { continue }
            discard(s.id)
        }
        for s in old.services where !settings.services.contains(where: { $0.id == s.id }) {
            discard(s.id)
        }
        focus.clamp(count: visible.count, columns: columns)
        if active == nil { keyboard.hide() }
    }

    private func discard(_ id: String) {
        if active?.id == id { active = nil }
        if presented?.id == id {
            presentation += 1
            presented = nil
            zoomed = false
        }
        playing.remove(id)
        loading.remove(id)
        recents.remove(id)
        if audioServiceID == id { audioServiceID = nil }
        switcher.remove(id)
        web.discard(id)
    }

    // MARK: Motion

    static let zoomIn = Animation.spring(duration: 0.55, bounce: 0)
    static let zoomOut = Animation.spring(duration: 0.45, bounce: 0)
}
