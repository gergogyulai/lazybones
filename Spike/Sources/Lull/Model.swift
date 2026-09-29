import AppKit
import SiriRemote
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var selected = 0
    @Published var active: Service?
    @Published var showDebug: Bool
    @Published var settings: LauncherSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    @Published var reports: [String: [String: String]] = [:]
    @Published var events: [String] = []
    @Published var remoteStatus = SiriRemote.Status()
    /// Non-nil while the volume HUD is on screen.
    @Published var volumeHUD: VolumeState?

    /// Bumped to ask the UI to open the Settings window (only views can do that).
    @Published var settingsRequests = 0

    let remote = SiriRemote()
    let controlCenter = ControlCenter()
    let keyboard = KeyboardController()
    let web = WebPool()
    let extensions = Extensions()
    let tv = TVLink()
    private(set) lazy var simulator = RemoteSimulator { [unowned self] in handle($0, simulated: true) }
    private(set) lazy var audio = VolumeRouter(tv: tv, web: web) { [unowned self] in settings.tvVolume }
    var columns: Int { settings.columns }
    var visible: [Service] { settings.visibleServices }
    private let echo = CommandLine.arguments.contains("--log")
    private var keyMonitor: Any?
    private var volumeHUDHide: Task<Void, Never>?
    private var lastTVStatus = TVLink.Status.off

    init() {
        settings = LauncherSettings.load()
        showDebug = LauncherSettings.load().showDebugOnLaunch
        remote.onEvent = { [weak self] in self?.handle($0) }
        controlCenter.audio = audio
        controlCenter.tv = tv
        tv.onPaired = { [weak self] key in self?.settings.tv?.clientKey = key }
        tv.onChange = { [weak self] in
            guard let self else { return }
            if tv.status != lastTVStatus {
                lastTVStatus = tv.status
                log("tv \(tv.name): \(tv.status)")
            }
            if volumeHUD != nil, let state = audio.state() { volumeHUD = state }
            if controlCenter.isOpen { controlCenter.volume = audio.state() }
        }
        tv.configure(settings.tv)
        keyboard.layout = settings.keyboardLayout
        keyboard.onEdit = { [weak self] in self?.keyboardEdit($0) }
        web.onKeyboard = { [weak self] id, message in self?.keyboardMessage(id, message) }
        remote.onDiagnostic = { [weak self] in self?.log("remote: \($0)") }
        remote.onStatusChange = { [weak self] status in
            guard let self else { return }
            let old = remoteStatus
            remoteStatus = status
            if status.buttons != old.buttons || status.touch != old.touch {
                log("remote: buttons \(status.buttons), touch \(status.touch ? "connected" : "not found")")
            }
        }
        web.onReport = { [weak self] id, k, v in
            guard let self else { return }
            reports[id, default: [:]][k] = v
            if k != "video" { log("\(id) · \(k): \(v)") } else if echo { print("\(id) · video: \(v)") }
        }
        let initial = CommandLine.arguments.firstIndex(of: "--open").flatMap { i in
            LauncherSettings.load().services.first { i + 1 < CommandLine.arguments.count && $0.id == CommandLine.arguments[i + 1] }
        }
        if !CommandLine.arguments.contains("--no-ext") {
            web.extensions = extensions
            extensions.onStatus = { [weak self] in self?.log($0) }
            Task {
                await extensions.loadBundled()
                if let i = CommandLine.arguments.firstIndex(of: "--open-delay"), i + 1 < CommandLine.arguments.count,
                   let secs = Double(CommandLine.arguments[i + 1]) {
                    try? await Task.sleep(for: .seconds(secs))
                }
                if let initial { open(initial) }
            }
        } else if let initial {
            open(initial)
        }
        remote.start()
        if CommandLine.arguments.contains("--remote") { DispatchQueue.main.async { self.simulator.show() } }

        // Keyboard fallback for the launcher; inside a service the page gets keys directly.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            MainActor.assumeIsolated { self?.launcherKey(ev) ?? false } ? nil : ev
        }
    }

    /// `simulated` events come from the on-screen remote, which macOS never acts on itself.
    func handle(_ event: RemoteEvent, simulated: Bool = false) {
        log("\(simulated ? "sim " : "")\(event.source) \(event.command)")
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
        case .siri: showDebug.toggle()
        case .volumeUp: changeVolume(simulated) { $0.change(by: 6) }
        case .volumeDown: changeVolume(simulated) { $0.change(by: -6) }
        case .mute: changeVolume(simulated) { $0.toggleMute() }
        default:
            if let s = active { web.send(event.command, to: s) } else { navigate(event.command) }
        }
    }

    /// Applies a volume change and shows the HUD. When the buttons aren't exclusive, macOS already
    /// acts on volume keys itself, but only for outputs with their own volume control; for the TV
    /// or app volume Lull still has to do it.
    private func changeVolume(_ simulated: Bool, _ change: (VolumeRouter) -> Void) {
        let systemActs = !simulated && remoteStatus.buttons != .exclusive && audio.systemHandlesVolume
        if !systemActs { change(audio) }
        volumeHUDHide?.cancel()
        volumeHUDHide = Task {
            if systemActs { try? await Task.sleep(for: .milliseconds(150)) }
            guard let state = audio.state() else { return }
            withAnimation(.spring(duration: 0.3)) { volumeHUD = state }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { volumeHUD = nil }
        }
    }

    func open(_ s: Service) {
        extensions.activate(web.view(for: s))
        active = s
        log("open \(s.name)")
    }

    private func settingsChanged(from old: LauncherSettings) {
        settings.save()
        keyboard.layout = settings.keyboardLayout
        if !settings.keyboard { keyboard.hide() }
        if settings.tv != old.tv { tv.configure(settings.tv) }
        // A service whose page settings changed gets a fresh web view next time it opens.
        for s in settings.services {
            guard let before = old.services.first(where: { $0.id == s.id }),
                  before.url != s.url || before.agent != s.agent || before.spatialNav != s.spatialNav else { continue }
            if active?.id == s.id { active = nil }
            web.discard(s.id)
        }
        for s in old.services where !settings.services.contains(where: { $0.id == s.id }) {
            if active?.id == s.id { active = nil }
            web.discard(s.id)
        }
        selected = min(selected, max(visible.count - 1, 0))
        if active == nil { keyboard.hide() }
    }

    func toggleControlCenter() {
        if controlCenter.isOpen { controlCenter.close() } else { controlCenter.open(canReload: active != nil) }
    }

    func perform(_ action: ControlCenter.Action) {
        controlCenter.close()
        switch action {
        case .close: break
        case .home: goHome()
        case .reload: reload()
        case .toggleDebug: showDebug.toggle()
        case .settings: settingsRequests += 1
        case .tvOff: tv.turnOff()
        case .sleep:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["displaysleepnow"]
            try? p.run()
        }
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

    // MARK: Keyboard

    private func keyboardMessage(_ id: String, _ message: [String: Any]) {
        guard let s = active, s.id == id else { return }
        let token = message["id"] as? Int ?? 0
        switch message["e"] as? String {
        case "focus":
            // TV-style sites (youtube.com/tv) bring their own remote-friendly keyboard.
            guard settings.keyboard, s.agent != .tv, let field = message["field"] as? [String: Any] else { return }
            var host = web.views[id]?.url?.host() ?? s.url.host() ?? ""
            if host.hasPrefix("www.") { host.removeFirst(4) }
            keyboard.show(FieldContext(field), value: message["value"] as? String ?? "", token: token, host: host)
        case "blur": keyboard.blurred(token: token)
        case "value": keyboard.update(message["value"] as? String ?? "", token: token)
        case "reset": keyboard.hide()
        default: break
        }
    }

    private func keyboardEdit(_ edit: KeyboardController.Edit) {
        guard let s = active else { return }
        let token = keyboard.token
        let apply: (Any?) -> Void = { [weak self] v in
            if let v = v as? String { self?.keyboard.update(v, token: token) }
        }
        switch edit {
        case let .insert(t): web.keyboard("insert", t, in: s, then: apply)
        case let .replace(t): web.keyboard("replace", t, in: s, then: apply)
        case .delete: web.keyboard("del", in: s, then: apply)
        case .clear: web.keyboard("clear", in: s, then: apply)
        case .dismiss: web.keyboard("dismiss", in: s)
        case .next:
            web.keyboard("next", in: s) { [weak self] moved in
                guard moved as? Bool != true else { return }
                self?.keyboard.hide()
                self?.keyboardEdit(.submit)
            }
        case .submit:
            web.pressReturn(s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.web.keyboard("settle", token, in: s)
            }
        }
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

    private func log(_ s: String) {
        let line = "\(Date().formatted(.dateTime.hour().minute().second())) \(s)"
        events.append(line)
        if events.count > 50 { events.removeFirst(events.count - 50) }
        if echo { print(line); fflush(stdout) }
    }
}
