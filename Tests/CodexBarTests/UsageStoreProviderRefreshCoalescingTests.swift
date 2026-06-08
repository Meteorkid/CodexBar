import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct UsageStoreProviderRefreshCoalescingTests {
    @Test
    func `overlapping refreshProvider calls coalesce to one follow up fetch`() async {
        let settings = self.makeSettingsStore(suite: "UsageStoreProviderRefreshCoalescingTests-overlap")
        settings.refreshFrequency = .manual
        let store = self.makeUsageStore(settings: settings)
        let fetchCounter = FetchCounter()
        let blocker = BlockingCodexFetchStrategy()
        self.installBlockingCodexProvider(on: store, blocker: blocker, counter: fetchCounter)

        let first = Task { await store.refreshProvider(.codex, allowDisabled: true) }
        await blocker.waitUntilStarted()

        let second = Task { await store.refreshProvider(.codex, allowDisabled: true) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.providerRefreshCoalesce.contains(.codex))

        await blocker.resume(with: .success(self.codexSnapshot(email: "a@example.com", usedPercent: 1)))
        await first.value
        await second.value

        let snapshot = self.codexSnapshot(email: "a@example.com", usedPercent: 2)
        if await fetchCounter.current() < 2 {
            await blocker.waitUntilStarted()
            await blocker.resume(with: .success(snapshot))
        }
        try? await Task.sleep(for: .milliseconds(50))

        let count = await fetchCounter.current()
        #expect(count == 2)
    }

    @Test
    func `refreshProvider during global refresh coalesces without fetching`() async {
        let settings = self.makeSettingsStore(suite: "UsageStoreProviderRefreshCoalescingTests-global")
        settings.refreshFrequency = .manual
        let store = self.makeUsageStore(settings: settings)
        let fetchCounter = FetchCounter()
        self.installImmediateCodexProvider(
            on: store,
            counter: fetchCounter,
            snapshot: self.codexSnapshot(email: "a@example.com", usedPercent: 1))

        store.isRefreshing = true
        await store.refreshProvider(.codex, allowDisabled: true)

        #expect(store.providerRefreshCoalesce.contains(.codex))
        #expect(await fetchCounter.current() == 0)
        #expect(store.refreshingProviders.contains(.codex) == false)
    }
}

@MainActor
extension UsageStoreProviderRefreshCoalescingTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
    }

    private func codexSnapshot(email: String, usedPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: usedPercent, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "Pro"))
    }

    private func installBlockingCodexProvider(
        on store: UsageStore,
        blocker: BlockingCodexFetchStrategy,
        counter: FetchCounter)
    {
        let baseSpec = store.providerSpecs[.codex]!
        store.providerSpecs[.codex] = CodexAccountScopedRefreshTests.makeCodexProviderSpec(baseSpec: baseSpec) {
            await counter.increment()
            return try await blocker.awaitResult()
        }
    }

    private func installImmediateCodexProvider(
        on store: UsageStore,
        counter: FetchCounter,
        snapshot: UsageSnapshot)
    {
        let baseSpec = store.providerSpecs[.codex]!
        store.providerSpecs[.codex] = CodexAccountScopedRefreshTests.makeCodexProviderSpec(baseSpec: baseSpec) {
            await counter.increment()
            return snapshot
        }
    }
}

private actor FetchCounter {
    private var value = 0

    func increment() {
        self.value += 1
    }

    func current() -> Int {
        self.value
    }
}
