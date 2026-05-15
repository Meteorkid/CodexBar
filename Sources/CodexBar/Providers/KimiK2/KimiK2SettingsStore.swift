import CodexBarCore
import Foundation

extension SettingsStore {
    var kimiK2BaseURL: String {
        get { self.configSnapshot.providerConfig(for: .kimik2)?.sanitizedBaseURL ?? "" }
        set {
            self.updateProviderConfig(provider: .kimik2) { entry in
                entry.apiBaseURL = self.normalizedConfigValue(newValue)
            }
        }
    }

    var kimiK2APIToken: String {
        get { self.configSnapshot.providerConfig(for: .kimik2)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .kimik2) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .kimik2, field: "apiKey", value: newValue)
        }
    }

    func ensureKimiK2APITokenLoaded() {}
}
