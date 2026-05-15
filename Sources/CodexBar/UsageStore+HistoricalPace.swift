import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    func supportsWeeklyPace(for provider: UsageProvider) -> Bool {
        self.historicalPaceStore.supportsWeeklyPace(for: provider)
    }

    func weeklyPace(provider: UsageProvider, window: RateWindow, now: Date = .init()) -> UsagePace? {
        self.historicalPaceStore.weeklyPace(provider: provider, window: window, now: now)
    }

    func recordCodexHistoricalSampleIfNeeded(snapshot: UsageSnapshot) {
        self.historicalPaceStore.recordCodexHistoricalSampleIfNeeded(snapshot: snapshot)
    }

    func refreshHistoricalDatasetIfNeeded() async {
        await self.historicalPaceStore.refreshHistoricalDatasetIfNeeded()
    }

    func backfillCodexHistoricalFromDashboardIfNeeded(
        _ dashboard: OpenAIDashboardSnapshot,
        authorityDecision: CodexDashboardAuthorityDecision,
        attachedAccountEmail: String?)
    {
        self.historicalPaceStore.backfillCodexHistoricalFromDashboardIfNeeded(
            dashboard,
            authorityDecision: authorityDecision,
            attachedAccountEmail: attachedAccountEmail)
    }
}
