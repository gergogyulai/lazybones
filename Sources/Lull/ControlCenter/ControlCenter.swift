import CoreAudio
import LGTV
import MacSystem
import SiriRemote
import SwiftUI

/// State and remote navigation for the Control Center panel. Actions that reach outside the
/// panel come back to AppModel as an `Action`.
@MainActor
final class ControlCenter: ObservableObject {
    enum Item: Hashable { case home, displayOff, tvOff, volume, output, reload, sleepMode, debug, settings }
    enum Action { case close, home, displayOff, tvOff, reload, toggleSleepMode, toggleDebug, settings }

    @Published var isOpen = false
    @Published var focus = Item.home
    @Published var volume: VolumeState?
    @Published var outputs: [AudioOutputs.Device] = []
    @Published var currentOutput: AudioDeviceID?
    /// The output list is expanded in place; `outputFocus` indexes into it.
    @Published var outputExpanded = false
    @Published var outputFocus = 0
    @Published var network = NetworkInfo()
    /// Whether a service is open, so Reload has something to act on.
    @Published var canReload = false
    /// Whether the Sleep Mode tile is shown (a setting), and whether Sleep Mode is on.
    @Published var showsSleepMode = false
    @Published var sleepModeOn = false

    private let audio: VolumeRouter
    private let tv: TVLink
    private let networkMonitor = NetworkMonitor()

    init(audio: VolumeRouter, tv: TVLink) {
        self.audio = audio
        self.tv = tv
        networkMonitor.onChange = { [weak self] in self?.network = $0 }
        networkMonitor.start()
    }

    var rows: [[Item]] {
        [tv.status == .connected ? [.home, .displayOff, .tvOff] : [.home, .displayOff],
         [.volume], [.output],
         (canReload ? [.reload] : []) + (showsSleepMode ? [.sleepMode] : []) + [.debug, .settings]]
    }

    func open(canReload: Bool, showsSleepMode: Bool, sleepModeOn: Bool) {
        self.canReload = canReload
        self.showsSleepMode = showsSleepMode
        self.sleepModeOn = sleepModeOn
        focus = .home
        outputExpanded = false
        refresh()
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { isOpen = true }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.25)) { isOpen = false }
        outputExpanded = false
    }

    func refresh() {
        volume = audio.state()
        outputs = AudioOutputs.all()
        currentOutput = AudioOutputs.defaultID()
        networkMonitor.refresh()
    }

    func handle(_ command: RemoteCommand) -> Action? {
        if outputExpanded { return handleOutputList(command) }
        guard let r = rows.firstIndex(where: { $0.contains(focus) }), let c = rows[r].firstIndex(of: focus) else {
            focus = .home
            return nil
        }
        switch command {
        case .up where r > 0: move(to: r - 1, from: c)
        case .down where r < rows.count - 1: move(to: r + 1, from: c)
        case .left, .right:
            let step = command == .left ? -1 : 1
            if focus == .volume { changeVolume(by: 6 * step) }
            else if rows[r].indices.contains(c + step) { withAnimation(focusAnimation) { focus = rows[r][c + step] } }
        case .select: return activate()
        case .back: return .close
        default: break
        }
        return nil
    }

    func changeVolume(by delta: Int) {
        audio.change(by: delta)
        volume = audio.state()
    }

    private let focusAnimation = Animation.spring(duration: 0.25, bounce: 0.2)

    private func move(to row: Int, from col: Int) {
        withAnimation(focusAnimation) { focus = rows[row][min(col, rows[row].count - 1)] }
    }

    private func activate() -> Action? {
        switch focus {
        case .home: return .home
        case .displayOff: return .displayOff
        case .tvOff: return .tvOff
        case .reload: return .reload
        case .sleepMode: return .toggleSleepMode
        case .debug: return .toggleDebug
        case .settings: return .settings
        case .volume:
            audio.toggleMute()
            volume = audio.state()
        case .output:
            outputs = AudioOutputs.all()
            currentOutput = AudioOutputs.defaultID()
            outputFocus = outputs.firstIndex { $0.id == currentOutput } ?? 0
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) { outputExpanded = true }
        }
        return nil
    }

    private func handleOutputList(_ command: RemoteCommand) -> Action? {
        switch command {
        case .up: withAnimation(focusAnimation) { outputFocus = max(0, outputFocus - 1) }
        case .down: withAnimation(focusAnimation) { outputFocus = min(outputs.count - 1, outputFocus + 1) }
        case .select:
            if outputs.indices.contains(outputFocus) {
                AudioOutputs.setDefault(outputs[outputFocus].id)
                currentOutput = AudioOutputs.defaultID()
                volume = audio.state()
            }
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) { outputExpanded = false }
        case .back:
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) { outputExpanded = false }
        default: break
        }
        return nil
    }
}
