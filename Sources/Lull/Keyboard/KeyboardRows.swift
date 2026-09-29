import SwiftUI

extension KeyboardController {
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
