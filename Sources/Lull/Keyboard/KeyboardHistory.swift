import Foundation

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
