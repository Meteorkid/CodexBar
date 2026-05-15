import CodexBarCore
import Foundation

// MARK: - Plan utilization history (delegation to PlanUtilizationStore)

extension UsageStore {
    func supportsPlanUtilizationHistory(for provider: UsageProvider) -> Bool {
        self.planUtilizationStore.supportsPlanUtilizationHistory(for: provider)
    }

    func planUtilizationHistory(for provider: UsageProvider) -> [PlanUtilizationSeriesHistory] {
        self.planUtilizationStore.planUtilizationHistory(for: provider)
    }

    func shouldShowRefreshingMenuCard(for provider: UsageProvider) -> Bool {
        self.planUtilizationStore.shouldShowRefreshingMenuCard(for: provider)
    }

    func shouldHidePlanUtilizationMenuItem(for provider: UsageProvider) -> Bool {
        self.planUtilizationStore.shouldHidePlanUtilizationMenuItem(for: provider)
    }

    func recordPlanUtilizationHistorySample(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        account: ProviderTokenAccount? = nil,
        shouldUpdatePreferredAccountKey: Bool = true,
        shouldAdoptUnscopedHistory: Bool = true,
        now: Date = Date())
        async
    {
        await self.planUtilizationStore.recordPlanUtilizationHistorySample(
            provider: provider,
            snapshot: snapshot,
            account: account,
            shouldUpdatePreferredAccountKey: shouldUpdatePreferredAccountKey,
            shouldAdoptUnscopedHistory: shouldAdoptUnscopedHistory,
            now: now)
    }

    nonisolated static func loadWeeklyLimitResetDetectorStates(from userDefaults: UserDefaults)
        -> [String: PlanUtilizationStore.WeeklyLimitResetDetectorState]
    {
        PlanUtilizationStore.loadWeeklyLimitResetDetectorStates(from: userDefaults)
    }

    #if DEBUG
    nonisolated static func _updatedPlanUtilizationEntriesForTesting(
        existingEntries: [PlanUtilizationHistoryEntry],
        entry: PlanUtilizationHistoryEntry) -> [PlanUtilizationHistoryEntry]?
    {
        PlanUtilizationStore._updatedPlanUtilizationEntriesForTesting(
            existingEntries: existingEntries,
            entry: entry)
    }

    nonisolated static func _updatedPlanUtilizationHistoriesForTesting(
        existingHistories: [PlanUtilizationSeriesHistory],
        samples: [PlanUtilizationSeriesHistory]) -> [PlanUtilizationSeriesHistory]?
    {
        PlanUtilizationStore._updatedPlanUtilizationHistoriesForTesting(
            existingHistories: existingHistories,
            samples: samples)
    }

    nonisolated static var _planUtilizationMaxSamplesForTesting: Int {
        PlanUtilizationStore._planUtilizationMaxSamplesForTesting
    }

    nonisolated static func _planUtilizationAccountKeyForTesting(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> String?
    {
        PlanUtilizationStore._planUtilizationAccountKeyForTesting(
            provider: provider,
            snapshot: snapshot)
    }

    nonisolated static func _planUtilizationTokenAccountKeyForTesting(
        provider: UsageProvider,
        account: ProviderTokenAccount) -> String?
    {
        PlanUtilizationStore._planUtilizationTokenAccountKeyForTesting(
            provider: provider,
            account: account)
    }

    nonisolated static func _codexLegacyPlanUtilizationEmailHashKeyForTesting(
        normalizedEmail: String) -> String
    {
        PlanUtilizationStore._codexLegacyPlanUtilizationEmailHashKeyForTesting(
            normalizedEmail: normalizedEmail)
    }
    #endif
}
