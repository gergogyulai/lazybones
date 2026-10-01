import AppKit
import SiriRemote
import SwiftUI

/// Apps that have been opened, most recent first. Pure bookkeeping.
struct Recents: Equatable {
    private(set) var ids: [String] = []

    mutating func touch(_ id: String) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
    }

    mutating func remove(_ id: String) { ids.removeAll { $0 == id } }
}

/// The app switcher: a row of the apps that are still running, opened with a double click of the
/// TV button. Select resumes an app, and up (a swipe up on the clickpad) closes it.
@MainActor
final class AppSwitcher: ObservableObject {
    enum Action: Equatable {
        case resume(Service)
        case quit(Service)
        case dismiss
    }

    @Published private(set) var isOpen = false
    @Published private(set) var apps: [Service] = []
    /// Index into `apps`.
    @Published var focus = 0
    /// What each app looked like when it was left.
    @Published private(set) var snapshots: [String: NSImage] = [:]

    /// Opens on the most recent app, which is the one just left.
    func open(_ apps: [Service]) {
        self.apps = apps
        focus = 0
        withAnimation(Motion.present) { isOpen = true }
    }

    func close() {
        withAnimation(Motion.dismiss) { isOpen = false }
    }

    func setSnapshot(_ image: NSImage?, for id: String) {
        if let image { snapshots[id] = image }
    }

    /// Takes an app out of the row after it has been closed.
    func remove(_ id: String) {
        snapshots[id] = nil
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.expand) {
            apps.remove(at: i)
            focus = min(focus, max(apps.count - 1, 0))
        }
    }

    func handle(_ command: RemoteCommand) -> Action? {
        let app = apps.indices.contains(focus) ? apps[focus] : nil
        switch command {
        case .left: withAnimation(Motion.focus) { focus = max(0, focus - 1) }
        case .right: withAnimation(Motion.focus) { focus = min(apps.count - 1, focus + 1) }
        case .up: if let app { return .quit(app) }
        case .select: return app.map(Action.resume) ?? .dismiss
        case .back: return .dismiss
        default: break
        }
        return nil
    }
}
