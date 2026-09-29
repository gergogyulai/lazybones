import Foundation

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
