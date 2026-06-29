import Foundation

/// Stores tiny observations about user behavior, locally.
/// Not "AI memory" — just simple key-value preferences noticed by Orbit.
final class UserPreferenceStore {
    static let shared = UserPreferenceStore()

    private let defaults = UserDefaults.standard
    private let prefix = "com.orbit.preference."

    func observe(_ key: String, value: String) {
        let fullKey = prefix + key
        var entries = defaults.array(forKey: fullKey) as? [String] ?? []
        entries.append(value)
        if entries.count > 20 {
            entries = Array(entries.suffix(10))
        }
        defaults.set(entries, forKey: fullKey)
    }

    func recentValues(for key: String) -> [String] {
        defaults.array(forKey: prefix + key) as? [String] ?? []
    }

    func mostFrequent(for key: String) -> String? {
        let values = recentValues(for: key)
        guard !values.isEmpty else { return nil }
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    func setPreference(_ key: String, value: String) {
        defaults.set(value, forKey: prefix + "pref." + key)
    }

    func getPreference(_ key: String) -> String? {
        defaults.string(forKey: prefix + "pref." + key)
    }

    func clear() {
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
