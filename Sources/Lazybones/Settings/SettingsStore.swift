import Foundation

/// Where `LauncherSettings` are kept: one JSON blob in UserDefaults.
struct SettingsStore {
    var defaults = UserDefaults.standard
    private let key = "launcherSettings"

    func load() -> LauncherSettings {
        guard let data = defaults.data(forKey: key) else { return LauncherSettings() }
        do {
            return try JSONDecoder().decode(LauncherSettings.self, from: data).mergingNewBuiltIns()
        } catch {
            // Settings this build can't read: set them aside rather than silently overwriting them.
            defaults.set(data, forKey: key + ".unreadable")
            NSLog("Lazybones: unreadable settings, using defaults (\(error))")
            return LauncherSettings()
        }
    }

    func save(_ settings: LauncherSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: key)
        } catch {
            NSLog("Lazybones: could not save settings (\(error))")
        }
    }
}
