import CodexBarCore
import Foundation

extension SettingsStore {
    var ernieBaseURL: String {
        get { self.configSnapshot.providerConfig(for: .ernie)?.sanitizedBaseURL ?? "" }
        set {
            self.updateProviderConfig(provider: .ernie) { entry in
                entry.apiBaseURL = self.normalizedConfigValue(newValue)
            }
        }
    }

    var ernieAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .ernie)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .ernie) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .ernie, field: "apiKey", value: newValue)
        }
    }

    var ernieManualCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .ernie)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .ernie) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .ernie, field: "cookieHeader", value: newValue)
        }
    }

    var ernieCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .ernie, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .ernie) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .ernie, field: "cookieSource", value: newValue.rawValue)
        }
    }
}

extension SettingsStore {
    func ernieSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot.ErnieProviderSettings {
        _ = tokenOverride
        return ProviderSettingsSnapshot.ErnieProviderSettings(
            cookieSource: self.ernieCookieSource,
            manualCookieHeader: self.ernieManualCookieHeader)
    }
}
