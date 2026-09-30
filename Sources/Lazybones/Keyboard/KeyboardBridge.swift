import Foundation

/// Connects the on-screen keyboard to the page: field focus and value changes coming from
/// `Scripts.keyboard` go to the keyboard, and the keyboard's edits go back into the page's field.
@MainActor
final class KeyboardBridge {
    private let keyboard: KeyboardController
    private let web: WebPool
    private let activeService: () -> Service?
    private let isEnabled: () -> Bool

    init(keyboard: KeyboardController, web: WebPool, activeService: @escaping () -> Service?,
         isEnabled: @escaping () -> Bool) {
        self.keyboard = keyboard
        self.web = web
        self.activeService = activeService
        self.isEnabled = isEnabled
        web.onKeyboard = { [weak self] id, message in self?.pageMessage(from: id, message) }
        keyboard.onEdit = { [weak self] in self?.edit($0) }
    }

    // MARK: Page → keyboard

    private func pageMessage(from id: String, _ message: [String: Any]) {
        guard let s = activeService(), s.id == id else { return }
        let token = message["id"] as? Int ?? 0
        switch message["e"] as? String {
        case "focus":
            // TV-style sites (youtube.com/tv) bring their own remote-friendly keyboard.
            guard isEnabled(), s.agent != .tv, let field = message["field"] as? [String: Any] else { return }
            var host = web.views[id]?.url?.host() ?? s.url.host() ?? ""
            if host.hasPrefix("www.") { host.removeFirst(4) }
            keyboard.show(FieldContext(field), value: message["value"] as? String ?? "", token: token, host: host)
        case "blur": keyboard.blurred(token: token)
        case "value": keyboard.update(message["value"] as? String ?? "", token: token)
        case "reset": keyboard.hide()
        default: break
        }
    }

    // MARK: Keyboard → page

    private func edit(_ edit: KeyboardController.Edit) {
        guard let s = activeService() else { return }
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
                self?.edit(.submit)
            }
        case .submit:
            web.pressReturn(s)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                self?.web.keyboard("settle", token, in: s)
            }
        }
    }
}
