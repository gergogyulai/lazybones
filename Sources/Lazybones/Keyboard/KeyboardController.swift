import AppKit
import SiriRemote
import SwiftUI

enum KeyboardLayout: String, Codable, CaseIterable {
    case abc, qwerty
}

/// The on-screen keyboard: shown while a text field in the active page has focus, driven by the
/// remote. Key layout, suggestions and the Return key adapt to the field (see `FieldContext`).
@MainActor
final class KeyboardController: ObservableObject {
    enum Mode { case letters, symbols, accents, numpad }
    enum Shift { case off, once, locked }
    /// Changes to the page's field, carried out in the page by KeyboardBridge.
    enum Edit { case insert(String), delete, clear, replace(String), submit, next, dismiss }

    struct Key: Identifiable, Equatable {
        enum Kind { case char, function, action, chip, tool }
        enum Action: Equatable { case text(String), replace(String), shift, mode(Mode), space, delete, clear, paste, reveal, submit }

        let id: String
        let label: String
        var symbol: String? = nil
        /// In key widths; gaps between keys are `KeyboardController.gap`.
        var width: CGFloat = 1
        var kind = Kind.char
        let action: Action
    }

    /// Gap between keys, as a fraction of a key's width.
    static let gap: CGFloat = 0.14

    @Published private(set) var isVisible = false
    @Published private(set) var field: FieldContext?
    @Published private(set) var value = ""
    @Published private(set) var mode = Mode.letters
    @Published private(set) var shift = Shift.off
    @Published private(set) var focus = ""
    @Published private(set) var revealed = false
    /// The key just pressed, for a moment, so it can visibly click.
    @Published private(set) var flash: String?
    @Published var layout = KeyboardLayout.abc
    private(set) var host = ""
    /// Identifies the page's focused field; messages about an older field are ignored.
    private(set) var token = 0
    var onEdit: ((Edit) -> Void)?

    /// Horizontal position vertical moves aim for, so going down through the wide space bar and
    /// back up returns to the same column.
    private var preferredX: CGFloat = 0
    private var focusRow = 0
    private var hideTask: Task<Void, Never>?

    // MARK: Page events

    func show(_ f: FieldContext, value v: String, token t: Int, host h: String) {
        hideTask?.cancel()
        let sameField = isVisible && t == token
        token = t
        host = h
        value = v
        field = f
        if sameField {
            resolveFocus()
        } else {
            mode = f.kind.numeric ? .numpad : .letters
            revealed = false
            shift = .off
            autoShift()
            let rows = rows
            let first = rows.firstIndex { $0.contains { $0.kind == .char } } ?? 0
            place(rows, first, 0)
        }
        if !isVisible { withAnimation(.spring(duration: 0.45, bounce: 0.12)) { isVisible = true } }
    }

    /// Focus left the field. Waits a moment, since moving between fields blurs one before focusing the next.
    func blurred(token t: Int) {
        guard t == token else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func update(_ v: String, token t: Int? = nil) {
        if let t, t != token { return }
        guard v != value else { return }
        value = v
        autoShift()
        resolveFocus()
    }

    func hide() {
        hideTask?.cancel()
        guard isVisible else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0)) { isVisible = false }
    }

    /// Closes the keyboard and takes focus off the field, so it opens again only when selected.
    func dismiss() {
        guard isVisible else { return }
        remember()
        hide()
        onEdit?(.dismiss)
    }

    // MARK: Remote

    /// Returns false for commands the keyboard doesn't use.
    func handle(_ command: RemoteCommand) -> Bool {
        guard isVisible else { return false }
        switch command {
        case .up, .down, .left, .right: move(command)
        case .select: if let k = focusedKey { press(k) }
        case .back: dismiss()
        case .playPause: if mode != .numpad { cycleShift() }  // like tvOS: Play/Pause changes case
        default: return false
        }
        return true
    }

    func press(_ key: Key) {
        flashKey(key.id)
        switch key.action {
        case let .text(t): type(t)
        case .space: type(" ")
        case let .replace(t): onEdit?(.replace(t))
        case .shift: cycleShift()
        case let .mode(m):
            withAnimation(.snappy(duration: 0.25)) {
                mode = m
                shift = .off
                autoShift()
            }
            resolveFocus()
        case .delete: onEdit?(.delete)
        case .clear: onEdit?(.clear)
        case .reveal: withAnimation(.snappy) { revealed.toggle() }
        case .paste:
            guard var t = NSPasteboard.general.string(forType: .string) else { return }
            if field?.kind != .multiline {
                t = t.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }
            if !t.isEmpty { onEdit?(.insert(t)) }
        case .submit: submit()
        }
    }

    /// Focus from the mouse, for the remote simulator and trackpads.
    func hover(_ key: Key) {
        let rows = rows
        guard let r = rows.firstIndex(where: { $0.contains(key) }), let i = rows[r].firstIndex(of: key) else { return }
        set(rows, r, i, updateX: true)
    }

    private func type(_ t: String) {
        onEdit?(.insert(t))
        if shift == .once, mode == .letters || mode == .accents { shift = .off }
    }

    private func submit() {
        guard let f = field else { return }
        remember()
        switch f.action {
        case .next: onEdit?(.next)
        case .done: hide(); onEdit?(.dismiss)
        case .enter: hide(); onEdit?(.submit)
        }
    }

    private func remember() {
        guard let f = field else { return }
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if f.kind == .search, !v.isEmpty { KeyboardHistory.remember(search: v, host: host) }
        if f.kind == .email, v.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil {
            KeyboardHistory.remember(email: v)
        }
    }

    private func cycleShift() {
        withAnimation(.snappy(duration: 0.2)) {
            switch (mode, shift) {
            case (.symbols, .off): shift = .once
            case (.symbols, _): shift = .off
            case (_, .off): shift = .once
            case (_, .once): shift = .locked
            case (_, .locked): shift = .off
            }
        }
        resolveFocus()
    }

    /// Capitalizes the next letter where the field's `autocapitalize` says so.
    private func autoShift() {
        guard shift != .locked, mode == .letters || mode == .accents, let f = field else { return }
        let cap = switch f.capitalize {
        case .none: false
        case .all: true
        case .words: value.isEmpty || value.last?.isWhitespace == true
        case .sentences:
            value.isEmpty || value.last?.isNewline == true
                || (value.last == " " && [".", "!", "?"].contains(value.dropLast().last ?? " "))
        }
        shift = cap ? .once : .off
    }

    private func flashKey(_ id: String) {
        flash = id
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            if self?.flash == id { self?.flash = nil }
        }
    }

    // MARK: Focus

    var focusedKey: Key? { rows.lazy.flatMap { $0 }.first { $0.id == focus } }

    private func move(_ c: RemoteCommand) {
        let rows = rows
        guard let r = rows.firstIndex(where: { $0.contains { $0.id == focus } }),
              let i = rows[r].firstIndex(where: { $0.id == focus }) else { return resolveFocus() }
        switch c {
        case .left, .right:
            let j = i + (c == .left ? -1 : 1)
            if rows[r].indices.contains(j) { set(rows, r, j, updateX: true) }
        default:
            let r2 = r + (c == .up ? -1 : 1)
            if rows.indices.contains(r2) { set(rows, r2, Self.nearest(in: rows[r2], to: preferredX), updateX: false) }
        }
    }

    private func set(_ rows: [[Key]], _ r: Int, _ i: Int, updateX: Bool) {
        focusRow = r
        if updateX { preferredX = Self.centers(rows[r])[i] }
        withAnimation(.spring(duration: 0.22, bounce: 0.25)) { focus = rows[r][i].id }
    }

    private func place(_ rows: [[Key]], _ r: Int, _ i: Int) {
        guard rows.indices.contains(r), rows[r].indices.contains(i) else { return }
        focusRow = r
        preferredX = Self.centers(rows[r])[i]
        focus = rows[r][i].id
    }

    /// After the keys change (mode, case, suggestions), keep focus on the same key or the one
    /// closest to where it was.
    private func resolveFocus() {
        let rows = rows
        if let r = rows.firstIndex(where: { $0.contains { $0.id == focus } }) { focusRow = r; return }
        guard !rows.isEmpty else { return }
        let r = min(focusRow, rows.count - 1)
        focusRow = r
        focus = rows[r][Self.nearest(in: rows[r], to: preferredX)].id
    }

    static func width(of row: [Key]) -> CGFloat {
        row.reduce(0) { $0 + $1.width } + gap * CGFloat(max(row.count - 1, 0))
    }

    /// Key centers, with the row centered on 0.
    static func centers(_ row: [Key]) -> [CGFloat] {
        var x = -width(of: row) / 2
        return row.map { k in
            defer { x += k.width + gap }
            return x + k.width / 2
        }
    }

    private static func nearest(in row: [Key], to x: CGFloat) -> Int {
        centers(row).enumerated().min { abs($0.element - x) < abs($1.element - x) }?.offset ?? 0
    }

}
