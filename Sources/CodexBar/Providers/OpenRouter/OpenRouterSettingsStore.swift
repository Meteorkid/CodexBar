import CodexBarCore
import Foundation

extension SettingsStore {
    var openRouterBaseURL: String {
        get { self.configSnapshot.providerConfig(for: .openrouter)?.sanitizedBaseURL ?? "" }
        set {
            self.updateProviderConfig(provider: .openrouter) { entry in
                entry.apiBaseURL = self.normalizedConfigValue(newValue)
            }
        }
    }

    var openRouterAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .openrouter)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .openrouter) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .openrouter, field: "apiKey", value: newValue)
        }
    }
}
