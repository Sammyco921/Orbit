import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "settings")

@Observable
public final class AppSettings {
    private let keychain = KeychainManager()

    var providerType: ProviderType {
        didSet { save() }
    }
    var openAIKey: String {
        didSet { save() }
    }
    var anthropicKey: String {
        didSet { save() }
    }
    var localModelURL: String {
        didSet { save() }
    }
    var localModelName: String {
        didSet { save() }
    }
    var localAPIType: String {
        didSet { save() }
    }
    var useLocalEmbeddings: Bool {
        didSet { save() }
    }
    var enableCrossConversationMemory: Bool {
        didSet { save() }
    }
    var apiEnabled: Bool {
        didSet { save() }
    }
    var apiKey: String {
        didSet { save() }
    }
    var apiPort: UInt16 {
        didSet { save() }
    }
    var isDevelopmentMode: Bool {
        didSet { save() }
    }
    public var launchAtLogin: Bool {
        didSet { save() }
    }
    var hasCompletedOnboarding: Bool {
        didSet { save() }
    }

    init() {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: "providerType"),
           let type = ProviderType(rawValue: raw) {
            providerType = type
        } else {
            providerType = .openAI
        }

        // Try Keychain first, fall back to UserDefaults (migration)
        openAIKey = Self.readKeyFromKeychain(account: "openai") ?? defaults.string(forKey: "openAIKey") ?? ""
        anthropicKey = Self.readKeyFromKeychain(account: "anthropic") ?? defaults.string(forKey: "anthropicKey") ?? ""
        localModelURL = defaults.string(forKey: "localModelURL") ?? "http://localhost:11434"
        localModelName = defaults.string(forKey: "localModelName") ?? "llama3"
        localAPIType = defaults.string(forKey: "localAPIType") ?? LocalAPIType.ollama.rawValue
        useLocalEmbeddings = defaults.bool(forKey: "useLocalEmbeddings")
        enableCrossConversationMemory = defaults.object(forKey: "enableCrossConversationMemory") as? Bool ?? true
        apiEnabled = defaults.object(forKey: "apiEnabled") as? Bool ?? false
        if let stored = Self.readKeyFromKeychain(account: "orbitApi") ?? defaults.string(forKey: "apiKey"), !stored.isEmpty {
            apiKey = stored
        } else {
            let newKey = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            apiKey = newKey
            try? keychain.store(key: newKey, for: "orbitApi")
        }
        if let udKey = defaults.string(forKey: "apiKey"), !udKey.isEmpty, Self.readKeyFromKeychain(account: "orbitApi") == nil {
            try? keychain.store(key: udKey, for: "orbitApi")
            defaults.removeObject(forKey: "apiKey")
        }
        apiPort = UInt16(defaults.integer(forKey: "apiPort")) == 0 ? 8089 : UInt16(defaults.integer(forKey: "apiPort"))
        isDevelopmentMode = defaults.object(forKey: "isDevelopmentMode") as? Bool ?? false
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        hasCompletedOnboarding = defaults.object(forKey: "hasCompletedOnboarding") as? Bool ?? false

        // Migrate keys from UserDefaults to Keychain and clear UserDefaults
        migrateKeyIfNeeded(account: "openai", userDefaultsKey: "openAIKey")
        migrateKeyIfNeeded(account: "anthropic", userDefaultsKey: "anthropicKey")
    }

    private static func readKeyFromKeychain(account: String) -> String? {
        let km = KeychainManager()
        return try? km.read(account: account)
    }

    private func migrateKeyIfNeeded(account: String, userDefaultsKey: String) {
        let defaults = UserDefaults.standard
        guard let udValue = defaults.string(forKey: userDefaultsKey), !udValue.isEmpty else { return }

        // Already in Keychain? Skip.
        if (try? keychain.read(account: account)) != nil { return }

        do {
            try keychain.store(key: udValue, for: account)
            log.notice("Migrated \(account) key from UserDefaults to Keychain")
        } catch {
            log.error("Failed to migrate \(account) key: \(error.localizedDescription)")
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(providerType.rawValue, forKey: "providerType")
        defaults.set(localModelURL, forKey: "localModelURL")
        defaults.set(localModelName, forKey: "localModelName")
        defaults.set(localAPIType, forKey: "localAPIType")
        defaults.set(useLocalEmbeddings, forKey: "useLocalEmbeddings")
        defaults.set(enableCrossConversationMemory, forKey: "enableCrossConversationMemory")
        defaults.set(apiEnabled, forKey: "apiEnabled")
        writeKeyToKeychain(account: "orbitApi", value: apiKey)
        defaults.removeObject(forKey: "apiKey")
        defaults.set(apiPort, forKey: "apiPort")
        defaults.set(isDevelopmentMode, forKey: "isDevelopmentMode")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")

        // Store API keys in Keychain; clear UserDefaults after migration
        writeKeyToKeychain(account: "openai", value: openAIKey)
        writeKeyToKeychain(account: "anthropic", value: anthropicKey)

        defaults.removeObject(forKey: "openAIKey")
        defaults.removeObject(forKey: "anthropicKey")
    }

    private func writeKeyToKeychain(account: String, value: String) {
        if value.isEmpty {
            try? keychain.delete(account: account)
        } else {
            do {
                try keychain.store(key: value, for: account)
            } catch {
                log.error("Failed to store \(account) key in Keychain: \(error.localizedDescription)")
            }
        }
    }
}
