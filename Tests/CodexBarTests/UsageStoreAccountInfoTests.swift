import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct UsageStoreAccountInfoTests {
    @Test
    func `non-codex providers do not return codex auth fallback`() throws {
        let settings = self.makeSettingsStore(suite: "UsageStoreAccountInfoTests-non-codex")
        settings.statusChecksEnabled = false
        let managedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-info-non-codex-\(UUID().uuidString)", isDirectory: true)
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "codex-only@example.com",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        try Self.writeCodexAuthFile(homeURL: managedHome, email: "codex-only@example.com", plan: "plus")
        settings._test_activeManagedCodexAccount = managedAccount
        settings._test_activeManagedCodexRemoteHomePath = managedHome.path
        settings.codexActiveSource = .managedAccount(id: managedAccount.id)
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_activeManagedCodexRemoteHomePath = nil
            try? FileManager.default.removeItem(at: managedHome)
        }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)

        let claudeAccount = store.accountInfo(for: .claude)
        #expect(claudeAccount.email == nil)
        #expect(claudeAccount.plan == nil)

        let cursorAccount = store.accountInfo(for: .cursor)
        #expect(cursorAccount.email == nil)
        #expect(cursorAccount.plan == nil)
    }

    @Test
    func `codex provider still loads auth-backed account info`() throws {
        let settings = self.makeSettingsStore(suite: "UsageStoreAccountInfoTests-codex")
        settings.statusChecksEnabled = false
        let managedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-info-codex-\(UUID().uuidString)", isDirectory: true)
        let managedAccount = ManagedCodexAccount(
            id: UUID(),
            email: "codex@example.com",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        try Self.writeCodexAuthFile(homeURL: managedHome, email: "codex@example.com", plan: "team")
        settings._test_activeManagedCodexAccount = managedAccount
        settings._test_activeManagedCodexRemoteHomePath = managedHome.path
        settings.codexActiveSource = .managedAccount(id: managedAccount.id)
        defer {
            settings._test_activeManagedCodexAccount = nil
            settings._test_activeManagedCodexRemoteHomePath = nil
            try? FileManager.default.removeItem(at: managedHome)
        }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)

        let codexAccount = store.accountInfo(for: .codex)
        #expect(codexAccount.email == "codex@example.com")
        #expect(codexAccount.plan == "team")
    }

    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings._test_activeManagedCodexAccount = nil
        settings._test_activeManagedCodexRemoteHomePath = nil
        settings._test_unreadableManagedCodexAccountStore = false
        settings._test_managedCodexAccountStoreURL = nil
        settings._test_liveSystemCodexAccount = nil
        settings._test_codexReconciliationEnvironment = nil
        return settings
    }

    private static func writeCodexAuthFile(homeURL: URL, email: String, plan: String) throws {
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let auth = [
            "tokens": [
                "accessToken": "access-token",
                "refreshToken": "refresh-token",
                "idToken": Self.fakeJWT(email: email, plan: plan),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: auth)
        try data.write(to: homeURL.appendingPathComponent("auth.json"))
    }

    private static func fakeJWT(email: String, plan: String) -> String {
        let header = (try? JSONSerialization.data(withJSONObject: ["alg": "none"])) ?? Data()
        let payload = (try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "chatgpt_plan_type": plan,
        ])) ?? Data()

        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }

        return "\(base64URL(header)).\(base64URL(payload))."
    }
}
