import CodexBarCore
import Foundation

@MainActor
final class HistoricalPaceStore {
    private unowned var store: UsageStore

    init(store: UsageStore) {
        self.store = store
    }

    private static let minimumPaceExpectedPercent: Double = 3
    private static let backfillMaxTimestampMismatch: TimeInterval = 5 * 60

    func supportsWeeklyPace(for provider: UsageProvider) -> Bool {
        switch provider {
        case .codex, .claude, .opencode, .abacus:
            true
        default:
            false
        }
    }

    func weeklyPace(provider: UsageProvider, window: RateWindow, now: Date = .init()) -> UsagePace? {
        guard self.supportsWeeklyPace(for: provider) else { return nil }
        guard window.remainingPercent > 0 else { return nil }
        let resolved: UsagePace?
        if provider == .codex, store.settings.historicalTrackingEnabled {
            let codexAccountKey = store.codexOwnershipContext().canonicalKey
            if store.codexHistoricalDatasetAccountKey == codexAccountKey,
               let historical = CodexHistoricalPaceEvaluator.evaluate(
                   window: window,
                   now: now,
                   dataset: store.codexHistoricalDataset)
            {
                resolved = historical
            } else {
                resolved = UsagePace.weekly(window: window, now: now, defaultWindowMinutes: 10080)
            }
        } else {
            resolved = UsagePace.weekly(window: window, now: now, defaultWindowMinutes: 10080)
        }

        guard let resolved else { return nil }
        guard resolved.expectedUsedPercent >= Self.minimumPaceExpectedPercent else { return nil }
        return resolved
    }

    func recordCodexHistoricalSampleIfNeeded(snapshot: UsageSnapshot) {
        guard store.settings.historicalTrackingEnabled else { return }
        let projection = store.codexConsumerProjection(
            surface: .liveCard,
            snapshotOverride: snapshot,
            now: snapshot.updatedAt)
        guard let weekly = projection.rateWindow(for: .weekly) else { return }

        let sampledAt = snapshot.updatedAt
        let ownership = store.codexOwnershipContext(preferredEmail: snapshot.accountEmail(for: .codex))
        let historyStore = store.historicalUsageHistoryStore
        Task.detached(priority: .utility) { [weak self] in
            _ = await historyStore.recordCodexWeekly(
                window: weekly,
                sampledAt: sampledAt,
                accountKey: ownership.canonicalKey)
            let dataset = await historyStore.loadCodexDataset(
                canonicalAccountKey: ownership.canonicalKey,
                canonicalEmailHashKey: ownership.canonicalEmailHashKey,
                legacyEmailHash: ownership.historicalLegacyEmailHash,
                hasAdjacentMultiAccountVeto: ownership.hasAdjacentMultiAccountVeto)
            await MainActor.run { [weak self] in
                self?.setCodexHistoricalDataset(dataset, accountKey: ownership.canonicalKey)
            }
        }
    }

    func refreshHistoricalDatasetIfNeeded() async {
        if !store.settings.historicalTrackingEnabled {
            self.setCodexHistoricalDataset(nil, accountKey: nil)
            return
        }
        let ownership = store.codexOwnershipContext()
        let dataset = await store.historicalUsageHistoryStore.loadCodexDataset(
            canonicalAccountKey: ownership.canonicalKey,
            canonicalEmailHashKey: ownership.canonicalEmailHashKey,
            legacyEmailHash: ownership.historicalLegacyEmailHash,
            hasAdjacentMultiAccountVeto: ownership.hasAdjacentMultiAccountVeto)
        self.setCodexHistoricalDataset(dataset, accountKey: ownership.canonicalKey)
        if let dashboard = store.openAIDashboard {
            let authority = store.evaluateCodexDashboardAuthority(
                dashboard: dashboard,
                sourceKind: .liveWeb,
                routingTargetEmail: store.lastOpenAIDashboardTargetEmail)
            self.backfillCodexHistoricalFromDashboardIfNeeded(
                dashboard,
                authorityDecision: authority.decision,
                attachedAccountEmail: store.codexDashboardAttachmentEmail(from: authority.input))
        }
    }

    func backfillCodexHistoricalFromDashboardIfNeeded(
        _ dashboard: OpenAIDashboardSnapshot,
        authorityDecision: CodexDashboardAuthorityDecision,
        attachedAccountEmail: String?)
    {
        guard store.settings.historicalTrackingEnabled else { return }
        guard authorityDecision.allowedEffects.contains(.historicalBackfill) else { return }
        let usageBreakdown = OpenAIDashboardDailyBreakdown.removingSkillUsageServices(
            from: dashboard.usageBreakdown)
        guard !usageBreakdown.isEmpty else { return }

        let codexSnapshot = store.snapshots[.codex]
        let ownership = store.codexOwnershipContext(preferredEmail: attachedAccountEmail)
        let referenceWindow: RateWindow
        let calibrationAt: Date
        if let dashboardWeekly = CodexReconciledState.fromAttachedDashboard(
            snapshot: dashboard,
            provider: .codex,
            accountEmail: attachedAccountEmail,
            accountPlan: nil)?
            .weekly
        {
            referenceWindow = dashboardWeekly
            calibrationAt = dashboard.updatedAt
        } else if let codexSnapshot,
                  let snapshotWeekly = store.codexConsumerProjection(
                      surface: .liveCard,
                      snapshotOverride: codexSnapshot,
                      now: codexSnapshot.updatedAt).rateWindow(for: .weekly)
        {
            let mismatch = abs(codexSnapshot.updatedAt.timeIntervalSince(dashboard.updatedAt))
            guard mismatch <= Self.backfillMaxTimestampMismatch else { return }
            referenceWindow = snapshotWeekly
            calibrationAt = min(codexSnapshot.updatedAt, dashboard.updatedAt)
        } else {
            return
        }

        let historyStore = store.historicalUsageHistoryStore
        Task.detached(priority: .utility) { [weak self] in
            _ = await historyStore.backfillCodexWeeklyFromUsageBreakdown(
                usageBreakdown,
                referenceWindow: referenceWindow,
                now: calibrationAt,
                accountKey: ownership.canonicalKey)
            let dataset = await historyStore.loadCodexDataset(
                canonicalAccountKey: ownership.canonicalKey,
                canonicalEmailHashKey: ownership.canonicalEmailHashKey,
                legacyEmailHash: ownership.historicalLegacyEmailHash,
                hasAdjacentMultiAccountVeto: ownership.hasAdjacentMultiAccountVeto)
            await MainActor.run { [weak self] in
                self?.setCodexHistoricalDataset(dataset, accountKey: ownership.canonicalKey)
            }
        }
    }

    private func setCodexHistoricalDataset(_ dataset: CodexHistoricalDataset?, accountKey: String?) {
        store.codexHistoricalDataset = dataset
        store.codexHistoricalDatasetAccountKey = accountKey
        store.historicalPaceRevision += 1
    }
}
