import AppKit
import SiriRemote
import SwiftUI

enum KeyboardLayout: String, Codable, CaseIterable {
    case abc, qwerty
}

/// What the focused web field wants, read from its attributes and surroundings by `Scripts.keyboard`.
struct FieldContext: Equatable {
    enum Kind: Equatable {
        case text, search, email, url, password, number, phone, code, multiline

        var numeric: Bool { self == .number || self == .phone || self == .code }
    }

    enum Capitalize { case none, words, sentences, all }

    enum Action: Equatable {
        /// Sends Return to the page, under the label the field asks for.
        case enter(String, String)
        /// Moves to the next field of the form, like Tab.
        case next
        /// Just closes the keyboard (multi-line text, where Return would add a line).
        case done

        var label: String {
            switch self {
            case let .enter(label, _): label
            case .next: "Next"
            case .done: "Done"
            }
        }

        var symbol: String {
            switch self {
            case let .enter(_, symbol): symbol
            case .next: "arrow.right"
            case .done: "checkmark"
            }
        }
    }

    var kind: Kind
    var title: String
    var placeholder: String
    var maxLength: Int
    var capitalize: Capitalize
    var action: Action
    /// Choices the page offers itself, from a `<datalist>`.
    var options: [String]
    var decimal: Bool

    init(_ d: [String: Any]) {
        func s(_ k: String) -> String { d[k] as? String ?? "" }
        func b(_ k: String) -> Bool { d[k] as? Bool ?? false }

        let type = s("type").lowercased(), mode = s("inputMode").lowercased()
        let ac = Set(s("autocomplete").split(separator: " ").map(String.init))
        let label = s("label"), placeholder = s("placeholder")
        let words = [label, placeholder, s("name")].joined(separator: " ")
        func says(_ pattern: String) -> Bool {
            words.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let digitsOnly = s("pattern").range(of: #"^(\[0-9\]|\\d)(\*|\+|\{\d+(,\d*)?\})?$"#, options: .regularExpression) != nil

        var kind: Kind =
            if type == "password" { .password }
            else if ac.contains("one-time-code") { .code }
            else if type == "tel" || mode == "tel" || ac.contains(where: { $0.hasPrefix("tel") }) { .phone }
            else if type == "number" || mode == "numeric" || mode == "decimal" || digitsOnly
                || ac.contains(where: { $0.hasPrefix("cc-number") || $0 == "cc-csc" }) { .number }
            else if type == "email" || mode == "email" || ac.contains("email") || says(#"e-?mail"#) { .email }
            else if type == "url" || mode == "url" || ac.contains("url") { .url }
            else if type == "search" || mode == "search" || b("search") { .search }
            else if type == "textarea" || type == "contenteditable" { .multiline }
            else { .text }
        let maxLength = d["maxLength"] as? Int ?? 0
        // Short numeric fields labelled like a code are PINs and verification codes.
        if kind == .number, (4...8).contains(maxLength), says(#"code|pin|otp|verif|kód"#) { kind = .code }
        self.kind = kind
        self.maxLength = maxLength
        self.placeholder = placeholder
        self.options = d["options"] as? [String] ?? []
        decimal = mode == "decimal"

        let fallback = switch kind {
        case .search: "Search"
        case .email: "Email"
        case .url: "Web Address"
        case .password: "Password"
        case .phone: "Phone Number"
        case .code: "Code"
        case .number: "Number"
        case .text, .multiline: "Text"
        }
        title = !label.isEmpty ? label : !placeholder.isEmpty ? placeholder : fallback

        capitalize = switch s("autocapitalize").lowercased() {
        case "none", "off": .none
        case "words": .words
        case "characters": .all
        case "sentences", "on": .sentences
        default:
            if kind == .text, ac.contains(where: { $0.hasSuffix("name") && $0 != "username" }) || says(#"\bname\b|\bnév\b"#) { .words }
            else if kind == .multiline { .sentences }
            else { .none }
        }

        let hasNext = b("hasNext")
        action = switch s("enterKeyHint").lowercased() {
        case "next": hasNext ? .next : .enter("Next", "arrow.right")
        case "search": .enter("Search", "magnifyingglass")
        case "go": .enter("Go", "arrow.right")
        case "send": .enter("Send", "paperplane.fill")
        case "enter": .enter("Return", "return")
        case "done": kind == .multiline ? .done : .enter("Done", "checkmark")
        default:
            if kind == .search { .enter("Search", "magnifyingglass") }
            else if hasNext { .next }
            else if kind == .multiline { .done }
            else if b("login") { .enter("Sign In", "person.fill.checkmark") }
            else if b("inForm") { .enter("Go", "arrow.right") }
            else { .enter("Done", "checkmark") }
        }
    }
}

/// Recent searches (per site) and email addresses, offered as suggestions. Never passwords.
enum KeyboardHistory {
    private static let searchesKey = "keyboardHistory.searches"
    private static let emailsKey = "keyboardHistory.emails"

    static func searches(for host: String) -> [String] {
        (UserDefaults.standard.dictionary(forKey: searchesKey) as? [String: [String]])?[host] ?? []
    }

    static func remember(search: String, host: String) {
        var all = UserDefaults.standard.dictionary(forKey: searchesKey) as? [String: [String]] ?? [:]
        all[host] = bump(search, in: all[host] ?? [], keep: 12)
        UserDefaults.standard.set(all, forKey: searchesKey)
    }

    static var emails: [String] { UserDefaults.standard.stringArray(forKey: emailsKey) ?? [] }

    static func remember(email: String) {
        UserDefaults.standard.set(bump(email, in: emails, keep: 5), forKey: emailsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: searchesKey)
        UserDefaults.standard.removeObject(forKey: emailsKey)
    }

    private static func bump(_ item: String, in list: [String], keep: Int) -> [String] {
        Array(([item] + list.filter { $0.caseInsensitiveCompare(item) != .orderedSame }).prefix(keep))
    }
}

/// The on-screen keyboard: shown while a text field in the active page has focus, driven by the
/// remote. Key layout, suggestions and the Return key adapt to the field (see `FieldContext`).
@MainActor
final class KeyboardController: ObservableObject {
    enum Mode { case letters, symbols, accents, numpad }
    enum Shift { case off, once, locked }
    /// Changes to the page's field, carried out by AppModel through the web view.
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

    // MARK: Keys

    var rows: [[Key]] {
        guard let f = field else { return [] }
        let body: [[Key]] = switch mode {
        case .numpad: numpad(f)
        case .letters: withFunctionRow(letterRows(f), f)
        case .symbols: withFunctionRow(symbolRows, f)
        case .accents: withFunctionRow(accentRows, f)
        }
        return [accessory(f)] + body
    }

    private var cased: Bool { shift != .off }

    private func chars(_ s: String, cased: Bool = false) -> [Key] {
        s.map { c in
            let base = String(c)
            let upper = base.uppercased()
            let t = cased && upper.count == 1 ? upper : base  // ß stays ß rather than becoming SS
            return Key(id: "c:\(base)", label: t, action: .text(t))
        }
    }

    private func letterRows(_ f: FieldContext) -> [[Key]] {
        let letters = layout == .abc ? ["abcdefghi", "jklmnopqr", "stuvwxyz"] : ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        let extras = switch f.kind {
        case .email: "@."
        case .url: "./"
        default: "-'"
        }
        var rows = letters.map { chars($0, cased: cased) }
        rows[2] += chars(extras)
        return rows
    }

    private var symbolRows: [[Key]] {
        (shift == .off ? ["1234567890", "-/:;()$&@\"", ".,?!'#%*+="]
                       : ["[]{}<>^~|\\", "_€£¥•§°«»¿", "`¡…±×÷¶©®™"]).map { chars($0) }
    }

    private var accentRows: [[Key]] {
        ["áàâäãåæçð", "éèêëíìîïñ", "óòôöõőøœß", "úùûüűýÿþ"].map { chars($0, cased: cased) }
    }

    /// Mode keys, space, delete and the action key, with space stretched to line up with the rows above.
    private func withFunctionRow(_ rows: [[Key]], _ f: FieldContext) -> [[Key]] {
        var left: [Key] = []
        switch mode {
        case .letters, .accents:
            left.append(Key(id: "f:shift", label: "shift", symbol: shiftSymbol, width: 1.5, kind: .function, action: .shift))
        case .symbols:
            left.append(Key(id: "f:shift", label: shift == .off ? "#+=" : "123", width: 1.5, kind: .function, action: .shift))
        case .numpad: break
        }
        left.append(mode == .letters
            ? Key(id: "f:mode", label: "123", width: 1.5, kind: .function, action: .mode(.symbols))
            : Key(id: "f:mode", label: "ABC", width: 1.5, kind: .function, action: .mode(.letters)))
        let typesProse = [.text, .search, .multiline].contains(f.kind)
        if typesProse, mode != .accents {
            left.append(Key(id: "f:accents", label: "àé", width: 1.2, kind: .function, action: .mode(.accents)))
        }
        if f.kind == .email || f.kind == .url {
            left.append(Key(id: "f:com", label: ".com", width: 1.5, kind: .function, action: .text(".com")))
        }
        let right = [
            Key(id: "f:delete", label: "delete", symbol: "delete.left", width: 1.5, kind: .function, action: .delete),
            Key(id: "f:action", label: f.action.label, symbol: f.action.symbol, width: 2.4, kind: .action, action: .submit),
        ]
        let target = rows.map(Self.width).max() ?? 10
        let fixed = Self.width(of: left + right) + 2 * Self.gap
        let space = Key(id: "f:space", label: "space", width: max(2.5, target - fixed), kind: .function, action: .space)
        return rows + [left + [space] + right]
    }

    private var shiftSymbol: String {
        switch shift {
        case .off: "shift"
        case .once: "shift.fill"
        case .locked: "capslock.fill"
        }
    }

    private func numpad(_ f: FieldContext) -> [[Key]] {
        let w: CGFloat = 2.4
        func wide(_ keys: [Key]) -> [Key] { keys.map { var k = $0; k.width = w; return k } }
        var last: [Key] = []
        let extra = f.kind == .phone ? "+" : f.decimal ? "." : nil
        if let extra { last += wide(chars(extra)) }
        var zero = chars("0")[0]
        zero.width = extra == nil ? 2 * w + Self.gap : w
        last += [zero, Key(id: "f:delete", label: "delete", symbol: "delete.left", width: w, kind: .function, action: .delete)]
        return ["123", "456", "789"].map { wide(chars($0)) } + [last, [
            Key(id: "f:action", label: f.action.label, symbol: f.action.symbol, width: 3 * w + 2 * Self.gap,
                kind: .action, action: .submit),
        ]]
    }

    /// Suggestions for what's typed so far, then tools. Always has Paste, so rows keep their positions.
    private func accessory(_ f: FieldContext) -> [Key] {
        var tools: [Key] = []
        if f.kind == .password {
            tools.append(Key(id: "tool:reveal", label: revealed ? "Hide" : "Show", symbol: revealed ? "eye.slash" : "eye",
                             width: 1.9, kind: .tool, action: .reveal))
        }
        if !value.isEmpty {
            tools.append(Key(id: "tool:clear", label: "Clear", symbol: "xmark", width: 1.9, kind: .tool, action: .clear))
        }
        tools.append(Key(id: "tool:paste", label: "Paste", symbol: "doc.on.clipboard", width: 1.9, kind: .tool, action: .paste))

        var chips: [Key] = []
        var room = 11 - Self.width(of: tools)
        for s in suggestions(f) {
            let label = s.label.count > 28 ? String(s.label.prefix(27)) + "…" : s.label
            let w = max(1.5, CGFloat(label.count) * 0.21 + (s.symbol == nil ? 0.8 : 1.2))
            guard w + Self.gap <= room else { break }
            room -= w + Self.gap
            chips.append(Key(id: "chip:\(s.label)", label: label, symbol: s.symbol, width: w, kind: .chip, action: s.action))
        }
        return chips + tools
    }

    private static let domains = ["gmail.com", "icloud.com", "outlook.com", "yahoo.com", "hotmail.com", "proton.me"]

    private struct Suggestion {
        let label: String
        var symbol: String? = nil
        let action: Key.Action
    }

    private func suggestions(_ f: FieldContext) -> [Suggestion] {
        let v = value, q = v.lowercased()
        let recent = "clock.arrow.circlepath"
        switch f.kind {
        case .email:
            if let at = v.firstIndex(of: "@") {
                let typed = v[v.index(after: at)...].lowercased()
                return Self.domains.filter { $0.hasPrefix(typed) && $0 != typed }
                    .map { Suggestion(label: "@" + $0, action: .text(String($0.dropFirst(typed.count)))) }
            }
            let past = KeyboardHistory.emails.filter { $0.lowercased().hasPrefix(q) && $0.count > v.count }
                .map { Suggestion(label: $0, symbol: recent, action: .replace($0)) }
            if v.isEmpty { return past }
            return past + Self.domains.prefix(4).map { Suggestion(label: "@" + $0, action: .text("@" + $0)) }
        case .url:
            let parts = v.isEmpty ? ["https://", "www."] : v.hasSuffix(".") ? ["com", "net", "org", "io"] : [".com", ".net", ".org", "/"]
            return parts.map { Suggestion(label: $0, action: .text($0)) }
        case .search, .text, .multiline:
            let history = f.kind == .search ? KeyboardHistory.searches(for: host) : []
            var seen = Set<String>()
            let pool = f.options.map { Suggestion(label: $0, action: .replace($0)) }
                + history.map { Suggestion(label: $0, symbol: recent, action: .replace($0)) }
            return pool.filter {
                let l = $0.label.lowercased()
                return (q.isEmpty || (l.hasPrefix(q) && l != q)) && seen.insert(l).inserted
            }
        default:
            return []
        }
    }
}
