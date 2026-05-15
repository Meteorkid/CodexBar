import CodexBarCore
import Foundation

// MARK: - OpenAI web lifecycle (delegation to OpenAIWebStore)

extension UsageStore {
    func requestOpenAIDashboardRefreshIfStale(reason: String) {
        self.openAIWebStore.requestOpenAIDashboardRefreshIfStale(reason: reason)
    }

    func applyOpenAIDashboard(
        _ dash: OpenAIDashboardSnapshot,
        targetEmail: String?,
        expectedGuard: CodexAccountScopedRefreshGuard? = nil,
        refreshTaskToken: UUID? = nil,
        allowCodexUsageBackfill: Bool = true) async
    {
        await self.openAIWebStore.applyOpenAIDashboard(
            dash,
            targetEmail: targetEmail,
            expectedGuard: expectedGuard,
            refreshTaskToken: refreshTaskToken,
            allowCodexUsageBackfill: allowCodexUsageBackfill)
    }

    func applyOpenAIDashboardFailure(
        message: String,
        expectedGuard: CodexAccountScopedRefreshGuard? = nil,
        refreshTaskToken: UUID? = nil,
        routingTargetEmail: String? = nil) async
    {
        await self.openAIWebStore.applyOpenAIDashboardFailure(
            message: message,
            expectedGuard: expectedGuard,
            refreshTaskToken: refreshTaskToken,
            routingTargetEmail: routingTargetEmail)
    }

    func applyOpenAIDashboardLoginRequiredFailure(
        expectedGuard: CodexAccountScopedRefreshGuard? = nil,
        refreshTaskToken: UUID? = nil,
        routingTargetEmail: String? = nil) async
    {
        await self.openAIWebStore.applyOpenAIDashboardLoginRequiredFailure(
            expectedGuard: expectedGuard,
            refreshTaskToken: refreshTaskToken,
            routingTargetEmail: routingTargetEmail)
    }

    func refreshOpenAIDashboardIfNeeded(
        force: Bool = false,
        expectedGuard: CodexAccountScopedRefreshGuard? = nil,
        bypassCoalescing: Bool = false,
        allowCodexUsageBackfill: Bool = true) async
    {
        await self.openAIWebStore.refreshOpenAIDashboardIfNeeded(
            force: force,
            expectedGuard: expectedGuard,
            bypassCoalescing: bypassCoalescing,
            allowCodexUsageBackfill: allowCodexUsageBackfill)
    }

    func handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: String?) {
        self.openAIWebStore.handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: targetEmail)
    }

    func importOpenAIDashboardBrowserCookiesNow() async {
        await self.openAIWebStore.importOpenAIDashboardBrowserCookiesNow()
    }

    func currentCodexOpenAIWebTargetEmail(
        allowCurrentSnapshotFallback: Bool,
        allowLastKnownLiveFallback: Bool) -> String?
    {
        self.openAIWebStore.currentCodexOpenAIWebTargetEmail(
            allowCurrentSnapshotFallback: allowCurrentSnapshotFallback,
            allowLastKnownLiveFallback: allowLastKnownLiveFallback)
    }

    func invalidateOpenAIDashboardRefreshTask() {
        self.openAIWebStore.invalidateOpenAIDashboardRefreshTask()
    }

    func importOpenAIDashboardCookiesIfNeeded(
        targetEmail: String?,
        force: Bool,
        preferCachedCookieHeader: Bool? = nil) async -> String?
    {
        await self.openAIWebStore.importOpenAIDashboardCookiesIfNeeded(
            targetEmail: targetEmail,
            force: force,
            preferCachedCookieHeader: preferCachedCookieHeader)
    }

    func resetOpenAIWebState() {
        self.openAIWebStore.resetOpenAIWebState()
    }

    func codexAccountEmailForOpenAIDashboard(allowLastKnownLiveFallback: Bool = true) -> String? {
        self.openAIWebStore.codexAccountEmailForOpenAIDashboard(
            allowLastKnownLiveFallback: allowLastKnownLiveFallback)
    }

    func codexCookieCacheScopeForOpenAIWeb() -> CookieHeaderCache.Scope? {
        self.openAIWebStore.codexCookieCacheScopeForOpenAIWeb()
    }

    func syncOpenAIWebState() {
        self.openAIWebStore.syncOpenAIWebState()
    }
}
