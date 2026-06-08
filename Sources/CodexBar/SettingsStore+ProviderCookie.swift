import CodexBarCore
import Foundation

extension SettingsStore {
    func providerCookieHeader(for provider: UsageProvider) -> String {
        self.configSnapshot.providerConfig(for: provider)?.sanitizedCookieHeader ?? ""
    }

    func setProviderCookieHeader(_ value: String, for provider: UsageProvider) {
        self.updateProviderConfig(provider: provider) { entry in
            entry.cookieHeader = self.normalizedConfigValue(value)
        }
        self.logSecretUpdate(provider: provider, field: "cookieHeader", value: value)
    }

    func setProviderCookieSource(_ value: ProviderCookieSource, for provider: UsageProvider) {
        self.updateProviderConfig(provider: provider) { entry in
            entry.cookieSource = value
        }
        self.logProviderModeChange(provider: provider, field: "cookieSource", value: value.rawValue)
    }

    func providerSnapshotCookieHeader(
        provider: UsageProvider,
        tokenOverride: TokenAccountOverride?) -> String
    {
        let fallback = self.providerCookieHeader(for: provider)
        guard let support = TokenAccountSupportCatalog.support(for: provider),
              case .cookieHeader = support.injection
        else {
            return fallback
        }
        guard let account = ProviderTokenAccountSelection.selectedAccount(
            provider: provider,
            settings: self,
            override: tokenOverride)
        else {
            return fallback
        }
        return TokenAccountSupportCatalog.normalizedCookieHeader(account.token, support: support)
    }

    func providerSnapshotCookieSource(
        provider: UsageProvider,
        fallback: ProviderCookieSource,
        tokenOverride: TokenAccountOverride?) -> ProviderCookieSource
    {
        let resolved = self.resolvedCookieSource(provider: provider, fallback: fallback)
        guard let support = TokenAccountSupportCatalog.support(for: provider),
              support.requiresManualCookieSource
        else {
            return resolved
        }
        if self.tokenAccounts(for: provider).isEmpty { return resolved }
        return .manual
    }
}
