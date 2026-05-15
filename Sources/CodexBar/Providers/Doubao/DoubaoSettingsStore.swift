import CodexBarCore
import Foundation

extension SettingsStore {
    var doubaoBaseURL: String {
        get { self.configSnapshot.providerConfig(for: .doubao)?.sanitizedBaseURL ?? "" }
        set {
            self.updateProviderConfig(provider: .doubao) { entry in
                entry.apiBaseURL = self.normalizedConfigValue(newValue)
            }
        }
    }

    var doubaoAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .doubao)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .doubao) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .doubao, field: "apiKey", value: newValue)
        }
    }

    var doubaoManualCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .doubao)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .doubao) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .doubao, field: "cookieHeader", value: newValue)
        }
    }

    var doubaoCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .doubao, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .doubao) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .doubao, field: "cookieSource", value: newValue.rawValue)
        }
    }
}

extension SettingsStore {
    func doubaoSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot.DoubaoProviderSettings {
        _ = tokenOverride
        return ProviderSettingsSnapshot.DoubaoProviderSettings(
            cookieSource: self.doubaoCookieSource,
            manualCookieHeader: self.doubaoManualCookieHeader)
    }
}
