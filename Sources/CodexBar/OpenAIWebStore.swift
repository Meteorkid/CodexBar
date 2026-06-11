import CodexBarCore
import Foundation

/// OpenAI Web Dashboard 的逻辑处理类。
/// 持有对 UsageStore 的引用以访问状态，所有方法在 MainActor 上下文中执行。
@MainActor
final class OpenAIWebStore {
    // MARK: - Store reference

    private unowned var store: UsageStore

    init(store: UsageStore) {
        self.store = store
    }

    // MARK: - Context types

    struct RefreshGateContext {
        let force: Bool
        let accountDidChange: Bool
        let lastError: String?
        let lastSnapshotAt: Date?
        let lastAttemptAt: Date?
        let now: Date
        let refreshInterval: TimeInterval
    }

    struct RefreshPolicyContext {
        let accessEnabled: Bool
        let batterySaverEnabled: Bool
        let force: Bool
    }

    // MARK: - Timeouts

    private static let refreshMultiplier: TimeInterval = 5
    private static let primaryFetchTimeout: TimeInterval = 25
    private static let retryFetchTimeout: TimeInterval = 8
    private static let postImportFetchTimeout: TimeInterval = 25

    static func dashboardFetchTimeout(didImportCookies: Bool) -> TimeInterval {
        didImportCookies ? postImportFetchTimeout : primaryFetchTimeout
    }

    static func retryDashboardFetchTimeout(afterCookieImport: Bool) -> TimeInterval {
        afterCookieImport ? postImportFetchTimeout : retryFetchTimeout
    }

    static func refreshIntervalSeconds(baseRefreshSeconds: TimeInterval) -> TimeInterval {
        let base = max(baseRefreshSeconds, 120)
        return base * refreshMultiplier
    }

    // MARK: - Policy decisions

    nonisolated static func shouldRunRefresh(_ context: RefreshPolicyContext) -> Bool {
        guard context.accessEnabled else { return false }
        return context.force || !context.batterySaverEnabled
    }

    nonisolated static func forceRefreshForStaleRequest(batterySaverEnabled: Bool) -> Bool {
        !batterySaverEnabled
    }

    nonisolated static func shouldSkipRefresh(_ context: RefreshGateContext) -> Bool {
        if context.force || context.accountDidChange { return false }
        if let lastAttemptAt = context.lastAttemptAt,
           context.now.timeIntervalSince(lastAttemptAt) < context.refreshInterval
        {
            return true
        }
        if context.lastError == nil,
           let lastSnapshotAt = context.lastSnapshotAt,
           context.now.timeIntervalSince(lastSnapshotAt) < context.refreshInterval
        {
            return true
        }
        return false
    }

    // MARK: - Error helpers

    static func isTimeout(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    static func friendlyError(
        body: String,
        targetEmail: String?,
        cookieImportStatus: String?) -> String?
    {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = cookieImportStatus?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [
                "OpenAI web dashboard returned an empty page.",
                "Sign in to chatgpt.com and update OpenAI cookies in Providers → Codex.",
            ].joined(separator: " ")
        }

        let lower = trimmed.lowercased()
        let looksLikePublicLanding = lower.contains("skip to content")
            && (lower.contains("about") || lower.contains("openai") || lower.contains("chatgpt"))
        let looksLoggedOut = lower.contains("sign in")
            || lower.contains("log in")
            || lower.contains("create account")
            || lower.contains("continue with google")
            || lower.contains("continue with apple")
            || lower.contains("continue with microsoft")

        guard looksLikePublicLanding || looksLoggedOut else { return nil }
        let emailLabel = targetEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetLabel = (emailLabel?.isEmpty == false) ? emailLabel! : "your OpenAI account"
        if let status, !status.isEmpty {
            if status.contains("cookies do not match Codex account")
                || status.localizedCaseInsensitiveContains("openai cookies are for")
                || status.localizedCaseInsensitiveContains("cookie import failed")
            {
                return "\(status) Switch chatgpt.com account, then refresh OpenAI cookies."
            }
        }
        return [
            "OpenAI web dashboard returned a public page (not signed in).",
            "Sign in to chatgpt.com as \(targetLabel), then update OpenAI cookies in Providers → Codex.",
        ].joined(separator: " ")
    }

    static func conciseCookieMismatchStatus(
        found: [String],
        targetEmail: String?) -> String
    {
        let normalizedFound = Array(Set(
            found
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }))
            .sorted()

        let foundLabel: String = switch normalizedFound.count {
        case 0:
            "another account"
        case 1:
            normalizedFound[0]
        case 2:
            "\(normalizedFound[0]) or \(normalizedFound[1])"
        default:
            "\(normalizedFound[0]) or \(normalizedFound.count - 1) other accounts"
        }

        let targetLabel = targetEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let targetLabel, !targetLabel.isEmpty else {
            return "OpenAI cookies are for \(foundLabel)."
        }
        return "OpenAI cookies are for \(foundLabel), not \(targetLabel)."
    }

    // MARK: - Lifecycle (instance methods)


    private struct OpenAIDashboardRefreshContext {
        let targetEmail: String?
        let allowCurrentSnapshotFallback: Bool
        let expectedGuard: CodexAccountScopedRefreshGuard?
        let refreshTaskToken: UUID
        let allowCodexUsageBackfill: Bool
    }

    private func openAIWebRefreshIntervalSeconds() -> TimeInterval {
        let base = max(store.settings.refreshFrequency.seconds ?? 0, 120)
        return OpenAIWebStore.refreshIntervalSeconds(baseRefreshSeconds: base)
    }

    func requestOpenAIDashboardRefreshIfStale(reason: String) {
        guard store.isEnabled(.codex),
              store.settings.openAIWebAccessEnabled,
              store.settings.codexCookieSource.isEnabled
        else { return }
        let now = Date()
        let refreshInterval = self.openAIWebRefreshIntervalSeconds()
        let lastUpdatedAt = store.openAIDashboard?.updatedAt ?? store.lastOpenAIDashboardSnapshot?.updatedAt
        if let lastUpdatedAt, now.timeIntervalSince(lastUpdatedAt) < refreshInterval { return }
        let stamp = now.formatted(date: .abbreviated, time: .shortened)
        self.logOpenAIWeb("[\(stamp)] OpenAI web refresh request: \(reason)")
        let forceRefresh = OpenAIWebStore.forceRefreshForStaleRequest(
            batterySaverEnabled: store.settings.openAIWebBatterySaverEnabled)
        store.openAIWebLogger.debug(
            "OpenAI web stale refresh gate",
            metadata: [
                "reason": reason,
                "force": forceRefresh ? "1" : "0",
                "batterySaverEnabled": store.settings.openAIWebBatterySaverEnabled ? "1" : "0",
                "interaction": ProviderInteractionContext.current == .userInitiated ? "user" : "background",
            ])
        let expectedGuard = store.currentCodexOpenAIWebRefreshGuard()
        Task { await self.refreshOpenAIDashboardIfNeeded(force: forceRefresh, expectedGuard: expectedGuard) }
    }

    func applyOpenAIDashboard(
        _ dash: OpenAIDashboardSnapshot,
        targetEmail: String?,
        expectedGuard: CodexAccountScopedRefreshGuard? = nil,
        refreshTaskToken: UUID? = nil,
        allowCodexUsageBackfill: Bool = true) async
    {
        guard self.shouldApplyOpenAIDashboardRefreshTask(token: refreshTaskToken) else { return }
        if let expectedGuard,
           !store.shouldApplyOpenAIDashboardRefreshGuard(
               expectedGuard: expectedGuard,
               routingTargetEmail: targetEmail)
        {
            return
        }

        let authority = store.evaluateCodexDashboardAuthority(
            dashboard: dash,
            sourceKind: .liveWeb,
            routingTargetEmail: targetEmail)
        let attachedAccountEmail = store.codexDashboardAttachmentEmail(from: authority.input)

        await self.applyOpenAIDashboardAuthorityDecision(
            authority.decision,
            dashboard: dash,
            authorityInput: authority.input,
            attachedAccountEmail: attachedAccountEmail,
            allowCodexUsageBackfill: allowCodexUsageBackfill)
    }

    func applyOpenAIDashboardFailure(
        message: String,
        expectedGuard: CodexAccountScopedRefreshGuard? = nil,
        refreshTaskToken: UUID? = nil,
        routingTargetEmail: String? = nil) async
    {
        guard self.shouldApplyOpenAIDashboardRefreshTask(token: refreshTaskToken) else { return }
        if let expectedGuard,
           !store.shouldApplyOpenAIWebNonSuccessResult(
               expectedGuard: expectedGuard,
               routingTargetEmail: routingTargetEmail)
        {
            return
        }
        if self.openAIWebManagedTargetStoreIsUnreadable() {
            await self.failClosedRefreshForUnreadableManagedCodexStore()
            return
        }
        if self.openAIWebManagedTargetIsMissing() {
            await self.failClosedRefreshForMissingManagedCodexTarget()
            return
        }

        OpenAIDashboardFetcher.evictAllCachedWebViews()
        await MainActor.run {
            if let cached = store.lastOpenAIDashboardSnapshot {
                store.openAIDashboard = cached
                store.openAIDashboardAttachmentAuthorized = store.lastOpenAIDashboardAttachmentAuthorized
                let stamp = cached.updatedAt.formatted(date: .abbreviated, time: .shortened)
                store.lastOpenAIDashboardError =
                    "Last OpenAI dashboard refresh failed: \(message). Cached values from \(stamp)."
            } else {
                store.lastOpenAIDashboardError = message
                store.openAIDashboard = nil
                store.openAIDashboardAttachmentAuthorized = false
            }
        }
    }

    func applyOpenAIDashboardLoginRequiredFailure(
        expectedGuard: CodexAccountScopedRefreshGuard? = nil,
        refreshTaskToken: UUID? = nil,
        routingTargetEmail: String? = nil) async
    {
        guard self.shouldApplyOpenAIDashboardRefreshTask(token: refreshTaskToken) else { return }
        if let expectedGuard,
           !store.shouldApplyOpenAIWebNonSuccessResult(
               expectedGuard: expectedGuard,
               routingTargetEmail: routingTargetEmail)
        {
            return
        }
        if self.openAIWebManagedTargetStoreIsUnreadable() {
            await self.failClosedRefreshForUnreadableManagedCodexStore()
            return
        }
        if self.openAIWebManagedTargetIsMissing() {
            await self.failClosedRefreshForMissingManagedCodexTarget()
            return
        }

        OpenAIDashboardFetcher.evictAllCachedWebViews()
        await MainActor.run {
            store.lastOpenAIDashboardError = [
                "OpenAI web access requires a signed-in chatgpt.com session.",
                "Sign in using \(store.codexBrowserCookieOrder.loginHint), " +
                    "then update OpenAI cookies in Providers → Codex.",
            ].joined(separator: " ")
            store.openAIDashboard = store.lastOpenAIDashboardSnapshot
            store.openAIDashboardAttachmentAuthorized = store.lastOpenAIDashboardAttachmentAuthorized
            store.openAIDashboardRequiresLogin = true
        }
    }

    private func failClosedOpenAIDashboardSnapshot() {
        self.applyOpenAIDashboardCleanup(Set(CodexDashboardCleanup.allCases), preserveVisibleDashboard: false)
        store.openAIDashboardRequiresLogin = true
    }

    private func applyOpenAIDashboardAuthorityDecision(
        _ decision: CodexDashboardAuthorityDecision,
        dashboard: OpenAIDashboardSnapshot,
        authorityInput: CodexDashboardAuthorityInput,
        attachedAccountEmail: String?,
        allowCodexUsageBackfill: Bool) async
    {
        switch decision.disposition {
        case .attach:
            store.openAIDashboard = dashboard
            store.openAIDashboardAttachmentAuthorized = true
            store.lastOpenAIDashboardSnapshot = dashboard
            store.lastOpenAIDashboardAttachmentAuthorized = true
            store.lastOpenAIDashboardError = nil
            store.openAIDashboardRequiresLogin = false

            if decision.allowedEffects.contains(.usageBackfill),
               allowCodexUsageBackfill,
               store.snapshots[.codex] == nil,
               let usage = dashboard.toUsageSnapshot(provider: .codex, accountEmail: attachedAccountEmail)
            {
                store.snapshots[.codex] = usage
                store.errors[.codex] = nil
                store.failureGates[.codex]?.recordSuccess()
                store.lastSourceLabels[.codex] = "openai-web"
            }

            if decision.allowedEffects.contains(.creditsAttachment),
               store.credits == nil,
               let credits = dashboard.toCreditsSnapshot()
            {
                store.credits = credits
                store.lastCreditsSnapshot = credits
                store.lastCreditsSnapshotAccountKey = UsageStore.normalizeCodexAccountScopedKey(attachedAccountEmail)
                store.lastCreditsSource = .dashboardWeb
                store.lastCreditsError = nil
                store.creditsFailureStreak = 0
            }

            if decision.allowedEffects.contains(.refreshGuardSeed) {
                store.seedCodexAccountScopedRefreshGuard(accountEmail: attachedAccountEmail)
            }

            if let attachedAccountEmail, !attachedAccountEmail.isEmpty {
                OpenAIDashboardCacheStore.save(OpenAIDashboardCache(
                    accountEmail: attachedAccountEmail,
                    snapshot: dashboard))
            }

            if decision.allowedEffects.contains(.historicalBackfill) {
                store.backfillCodexHistoricalFromDashboardIfNeeded(
                    dashboard,
                    authorityDecision: decision,
                    attachedAccountEmail: attachedAccountEmail)
            }

        case .displayOnly:
            self.applyOpenAIDashboardCleanup(decision.cleanup, preserveVisibleDashboard: true)
            store.openAIDashboard = dashboard
            store.openAIDashboardAttachmentAuthorized = false
            store.lastOpenAIDashboardSnapshot = dashboard
            store.lastOpenAIDashboardAttachmentAuthorized = false
            store.lastOpenAIDashboardError = nil
            store.openAIDashboardRequiresLogin = false

        case .failClosed:
            self.applyOpenAIDashboardCleanup(decision.cleanup, preserveVisibleDashboard: false)
            store.lastOpenAIDashboardError = self.openAIDashboardPolicyFailureMessage(
                for: decision,
                authorityInput: authorityInput)
            store.openAIDashboardRequiresLogin = true
        }
    }

    private func applyOpenAIDashboardCleanup(
        _ cleanup: Set<CodexDashboardCleanup>,
        preserveVisibleDashboard: Bool)
    {
        if cleanup.contains(.dashboardDerivedUsage) {
            self.clearDashboardDerivedCodexUsageIfNeeded()
        }
        if cleanup.contains(.dashboardDerivedCredits) {
            self.clearDashboardDerivedCreditsIfNeeded()
        }
        if cleanup.contains(.dashboardRefreshGuardSeed) {
            self.clearDashboardRefreshGuardSeedIfNeeded()
        }
        if cleanup.contains(.dashboardCache) {
            OpenAIDashboardCacheStore.clear()
        }
        if cleanup.contains(.dashboardSnapshot), !preserveVisibleDashboard {
            store.openAIDashboard = nil
            store.openAIDashboardAttachmentAuthorized = false
            store.lastOpenAIDashboardSnapshot = nil
            store.lastOpenAIDashboardAttachmentAuthorized = false
        }
    }

    private func clearDashboardDerivedCodexUsageIfNeeded() {
        guard store.lastSourceLabels[.codex] == "openai-web" else { return }
        store.snapshots.removeValue(forKey: .codex)
        store.errors[.codex] = nil
        store.lastSourceLabels.removeValue(forKey: .codex)
        store.lastFetchAttempts.removeValue(forKey: .codex)
        store.accountSnapshots.removeValue(forKey: .codex)
        store.failureGates[.codex]?.reset()
        store.lastKnownSessionRemaining.removeValue(forKey: .codex)
        store.lastKnownSessionWindowSource.removeValue(forKey: .codex)
    }

    private func clearDashboardDerivedCreditsIfNeeded() {
        guard store.lastCreditsSource == .dashboardWeb else { return }
        store.credits = nil
        store.lastCreditsError = nil
        store.lastCreditsSnapshot = nil
        store.lastCreditsSnapshotAccountKey = nil
        store.lastCreditsSource = .none
        store.creditsFailureStreak = 0
    }

    private func clearDashboardRefreshGuardSeedIfNeeded() {
        store.lastCodexAccountScopedRefreshGuard = store.currentCodexAccountScopedRefreshGuard(
            preferCurrentSnapshot: false,
            allowLastKnownLiveFallback: false)
    }

    private func openAIDashboardPolicyFailureMessage(
        for decision: CodexDashboardAuthorityDecision,
        authorityInput: CodexDashboardAuthorityInput) -> String
    {
        switch decision.reason {
        case let .wrongEmail(expected, actual):
            [
                "OpenAI dashboard signed in as \(actual ?? "unknown"), but Codex uses \(expected ?? "unknown").",
                "Switch accounts in your browser and update OpenAI cookies in Providers → Codex.",
            ].joined(separator: " ")
        case let .sameEmailAmbiguity(email):
            "OpenAI dashboard ownership is ambiguous for \(email); Codex will not attach dashboard data."
        case .missingDashboardSignedInEmail:
            "OpenAI dashboard did not report a signed-in account. Refresh OpenAI cookies and try again."
        case .unresolvedWithoutTrustedEvidence:
            "OpenAI dashboard ownership could not be verified for the active Codex account."
        case .providerAccountMissingScopedEmail:
            "Codex account ownership could not be verified because the scoped email is unavailable."
        case .providerAccountLacksExactOwnershipProof:
            [
                "OpenAI dashboard ownership could not be matched to the active Codex account.",
                "Refresh Codex account data, then retry OpenAI web access.",
            ].joined(separator: " ")
        case .exactProviderAccountMatch,
             .trustedEmailMatchNoCompetingOwner,
             .trustedContinuityNoCompetingOwner:
            "OpenAI dashboard ownership policy blocked this dashboard."
        }
    }

    func refreshOpenAIDashboardIfNeeded(
        force: Bool = false,
        expectedGuard: CodexAccountScopedRefreshGuard? = nil,
        bypassCoalescing: Bool = false,
        allowCodexUsageBackfill: Bool = true) async
    {
        self.syncOpenAIWebState()
        guard store.isEnabled(.codex),
              store.settings.openAIWebAccessEnabled,
              store.settings.codexCookieSource.isEnabled
        else { return }
        if self.openAIWebManagedTargetStoreIsUnreadable() {
            await self.failClosedRefreshForUnreadableManagedCodexStore()
            return
        }
        if self.openAIWebManagedTargetIsMissing() {
            await self.failClosedRefreshForMissingManagedCodexTarget()
            return
        }

        let allowCurrentSnapshotFallback = expectedGuard?.source == .liveSystem && expectedGuard?
            .identity == .unresolved
        let targetEmail = self.currentCodexOpenAIWebTargetEmail(
            allowCurrentSnapshotFallback: allowCurrentSnapshotFallback,
            allowLastKnownLiveFallback: expectedGuard?.identity != .unresolved)
        let refreshKey = self.openAIDashboardRefreshKey(targetEmail: targetEmail, expectedGuard: expectedGuard)
        if !bypassCoalescing,
           let task = store.openAIDashboardRefreshTask,
           store.openAIDashboardRefreshTaskKey == refreshKey
        {
            await task.value
            return
        }
        self.handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: targetEmail)

        let now = Date()
        let minInterval = self.openAIWebRefreshIntervalSeconds()
        let refreshGate = OpenAIWebStore.RefreshGateContext(
            force: force,
            accountDidChange: store.openAIWebAccountDidChange,
            lastError: store.lastOpenAIDashboardError,
            lastSnapshotAt: store.lastOpenAIDashboardSnapshot?.updatedAt,
            lastAttemptAt: store.lastOpenAIDashboardAttemptAt,
            now: now,
            refreshInterval: minInterval)
        if OpenAIWebStore.shouldSkipRefresh(refreshGate) {
            return
        }
        store.lastOpenAIDashboardAttemptAt = now

        let taskToken = UUID()
        let context = OpenAIDashboardRefreshContext(
            targetEmail: targetEmail,
            allowCurrentSnapshotFallback: allowCurrentSnapshotFallback,
            expectedGuard: expectedGuard,
            refreshTaskToken: taskToken,
            allowCodexUsageBackfill: allowCodexUsageBackfill)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performOpenAIDashboardRefreshIfNeeded(context)
        }
        store.openAIDashboardRefreshTask = task
        store.openAIDashboardRefreshTaskKey = refreshKey
        store.openAIDashboardRefreshTaskToken = taskToken
        await task.value
        if store.openAIDashboardRefreshTaskToken == taskToken {
            store.openAIDashboardRefreshTask = nil
            store.openAIDashboardRefreshTaskKey = nil
            store.openAIDashboardRefreshTaskToken = nil
        }
    }

    private func performOpenAIDashboardRefreshIfNeeded(_ context: OpenAIDashboardRefreshContext) async {
        store.openAIDashboardCookieImportStatus = nil
        var latestCookieImportStatus: String?
        if store.openAIWebDebugLines.isEmpty {
            self.resetOpenAIWebDebugLog(context: "refresh")
        } else {
            let stamp = Date().formatted(date: .abbreviated, time: .shortened)
            self.logOpenAIWeb("[\(stamp)] OpenAI web refresh start")
        }
        let log: (String) -> Void = { [weak self] line in
            guard let self else { return }
            self.logOpenAIWeb(line)
        }

        do {
            let normalized = context.targetEmail?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            var effectiveEmail = context.targetEmail

            // Use a per-email persistent `WKWebsiteDataStore` so multiple dashboard sessions can coexist.
            // Strategy:
            // - Try the existing per-email WebKit cookie store first (fast; avoids Keychain prompts).
            // - On login-required or account mismatch, import cookies from the configured browser order and retry once.
            var didImportCookiesForRefresh = false
            if store.openAIWebAccountDidChange, let targetEmail = context.targetEmail, !targetEmail.isEmpty {
                // On account switches, proactively re-import cookies so we don't show stale data from the previous
                // user.
                let imported = await self.importOpenAIDashboardCookiesIfNeeded(
                    targetEmail: targetEmail,
                    force: true)
                didImportCookiesForRefresh = true
                latestCookieImportStatus = self.currentOpenAIDashboardCookieImportStatus()
                if await self.abortOpenAIDashboardRetryAfterImportFailure(
                    importedEmail: imported,
                    targetEmail: targetEmail,
                    expectedGuard: context.expectedGuard,
                    cookieImportStatus: latestCookieImportStatus,
                    refreshTaskToken: context.refreshTaskToken)
                {
                    store.openAIWebAccountDidChange = false
                    return
                }
                if let imported {
                    effectiveEmail = imported
                }
                store.openAIWebAccountDidChange = false
            }

            var dash = try await self.loadLatestOpenAIDashboard(
                accountEmail: effectiveEmail,
                logger: log,
                timeout: OpenAIWebStore.dashboardFetchTimeout(didImportCookies: didImportCookiesForRefresh))

            if self.dashboardEmailMismatch(expected: normalized, actual: dash.signedInEmail) {
                if let imported = await self.importOpenAIDashboardCookiesIfNeeded(
                    targetEmail: context.targetEmail,
                    force: true)
                {
                    effectiveEmail = imported
                }
                latestCookieImportStatus = self.currentOpenAIDashboardCookieImportStatus()
                dash = try await self.loadLatestOpenAIDashboard(
                    accountEmail: effectiveEmail,
                    logger: log,
                    timeout: OpenAIWebStore.retryDashboardFetchTimeout(afterCookieImport: true))
            }

            await self.applyOpenAIDashboard(
                dash,
                targetEmail: effectiveEmail,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                allowCodexUsageBackfill: context.allowCodexUsageBackfill)
        } catch let OpenAIDashboardFetcher.FetchError.noDashboardData(body) {
            await self.retryOpenAIDashboardAfterNoData(
                body: body,
                context: context,
                latestCookieImportStatus: &latestCookieImportStatus,
                logger: log)
        } catch OpenAIDashboardFetcher.FetchError.loginRequired {
            await self.retryOpenAIDashboardAfterLoginRequired(
                context: context,
                latestCookieImportStatus: &latestCookieImportStatus,
                logger: log)
        } catch {
            if OpenAIWebStore.isTimeout(error) {
                await self.retryOpenAIDashboardAfterTimeout(
                    context: context,
                    latestCookieImportStatus: &latestCookieImportStatus,
                    logger: log)
                return
            }
            let message = self.preferredOpenAIDashboardFailureMessage(
                error: error,
                targetEmail: context.targetEmail,
                cookieImportStatus: latestCookieImportStatus)
            await self.applyOpenAIDashboardFailure(
                message: message,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                routingTargetEmail: context.targetEmail)
        }
    }

    private func retryOpenAIDashboardAfterTimeout(
        context: OpenAIDashboardRefreshContext,
        latestCookieImportStatus: inout String?,
        logger: @escaping (String) -> Void) async
    {
        let targetEmail = self.currentCodexOpenAIWebTargetEmail(
            allowCurrentSnapshotFallback: context.allowCurrentSnapshotFallback,
            allowLastKnownLiveFallback: context.expectedGuard?.identity != .unresolved)
        var effectiveEmail = targetEmail
        let imported = await self.importOpenAIDashboardCookiesIfNeeded(
            targetEmail: targetEmail,
            force: true,
            preferCachedCookieHeader: true)
        latestCookieImportStatus = self.currentOpenAIDashboardCookieImportStatus()
        if await self.abortOpenAIDashboardRetryAfterImportFailure(
            importedEmail: imported,
            targetEmail: targetEmail,
            expectedGuard: context.expectedGuard,
            cookieImportStatus: latestCookieImportStatus,
            refreshTaskToken: context.refreshTaskToken)
        {
            return
        }
        if let imported {
            effectiveEmail = imported
        }
        do {
            let dash = try await self.loadLatestOpenAIDashboard(
                accountEmail: effectiveEmail,
                logger: logger,
                timeout: OpenAIWebStore.retryDashboardFetchTimeout(afterCookieImport: true))
            await self.applyOpenAIDashboard(
                dash,
                targetEmail: effectiveEmail,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                allowCodexUsageBackfill: context.allowCodexUsageBackfill)
        } catch {
            let message = self.preferredOpenAIDashboardFailureMessage(
                error: error,
                targetEmail: targetEmail,
                cookieImportStatus: latestCookieImportStatus)
            await self.applyOpenAIDashboardFailure(
                message: message,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                routingTargetEmail: targetEmail)
        }
    }

    private func retryOpenAIDashboardAfterNoData(
        body: String,
        context: OpenAIDashboardRefreshContext,
        latestCookieImportStatus: inout String?,
        logger: @escaping (String) -> Void) async
    {
        let targetEmail = self.currentCodexOpenAIWebTargetEmail(
            allowCurrentSnapshotFallback: context.allowCurrentSnapshotFallback,
            allowLastKnownLiveFallback: context.expectedGuard?.identity != .unresolved)
        var effectiveEmail = targetEmail
        let imported = await self.importOpenAIDashboardCookiesIfNeeded(targetEmail: targetEmail, force: true)
        latestCookieImportStatus = self.currentOpenAIDashboardCookieImportStatus()
        if await self.abortOpenAIDashboardRetryAfterImportFailure(
            importedEmail: imported,
            targetEmail: targetEmail,
            expectedGuard: context.expectedGuard,
            cookieImportStatus: latestCookieImportStatus,
            refreshTaskToken: context.refreshTaskToken)
        {
            return
        }
        if let imported {
            effectiveEmail = imported
        }
        do {
            let dash = try await self.loadLatestOpenAIDashboard(
                accountEmail: effectiveEmail,
                logger: logger,
                timeout: OpenAIWebStore.retryDashboardFetchTimeout(afterCookieImport: true))
            await self.applyOpenAIDashboard(
                dash,
                targetEmail: effectiveEmail,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                allowCodexUsageBackfill: context.allowCodexUsageBackfill)
        } catch let OpenAIDashboardFetcher.FetchError.noDashboardData(retryBody) {
            let finalBody = retryBody.isEmpty ? body : retryBody
            let message = OpenAIWebStore.friendlyError(
                body: finalBody,
                targetEmail: targetEmail,
                cookieImportStatus: latestCookieImportStatus)
                ?? OpenAIDashboardFetcher.FetchError.noDashboardData(body: finalBody).localizedDescription
            await self.applyOpenAIDashboardFailure(
                message: message,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                routingTargetEmail: targetEmail)
        } catch {
            let message = self.preferredOpenAIDashboardFailureMessage(
                error: error,
                targetEmail: targetEmail,
                cookieImportStatus: latestCookieImportStatus)
            await self.applyOpenAIDashboardFailure(
                message: message,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                routingTargetEmail: targetEmail)
        }
    }

    private func retryOpenAIDashboardAfterLoginRequired(
        context: OpenAIDashboardRefreshContext,
        latestCookieImportStatus: inout String?,
        logger: @escaping (String) -> Void) async
    {
        let targetEmail = self.currentCodexOpenAIWebTargetEmail(
            allowCurrentSnapshotFallback: context.allowCurrentSnapshotFallback,
            allowLastKnownLiveFallback: context.expectedGuard?.identity != .unresolved)
        var effectiveEmail = targetEmail
        let imported = await self.importOpenAIDashboardCookiesIfNeeded(targetEmail: targetEmail, force: true)
        latestCookieImportStatus = self.currentOpenAIDashboardCookieImportStatus()
        if await self.abortOpenAIDashboardRetryAfterImportFailure(
            importedEmail: imported,
            targetEmail: targetEmail,
            expectedGuard: context.expectedGuard,
            cookieImportStatus: latestCookieImportStatus,
            refreshTaskToken: context.refreshTaskToken)
        {
            return
        }
        if let imported {
            effectiveEmail = imported
        }
        do {
            let dash = try await self.loadLatestOpenAIDashboard(
                accountEmail: effectiveEmail,
                logger: logger,
                timeout: OpenAIWebStore.retryDashboardFetchTimeout(afterCookieImport: true))
            await self.applyOpenAIDashboard(
                dash,
                targetEmail: effectiveEmail,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                allowCodexUsageBackfill: context.allowCodexUsageBackfill)
        } catch OpenAIDashboardFetcher.FetchError.loginRequired {
            await self.applyOpenAIDashboardLoginRequiredFailure(
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                routingTargetEmail: targetEmail)
        } catch {
            let message = self.preferredOpenAIDashboardFailureMessage(
                error: error,
                targetEmail: targetEmail,
                cookieImportStatus: latestCookieImportStatus)
            await self.applyOpenAIDashboardFailure(
                message: message,
                expectedGuard: context.expectedGuard,
                refreshTaskToken: context.refreshTaskToken,
                routingTargetEmail: targetEmail)
        }
    }

    // MARK: - OpenAI web account switching

    /// Detect Codex account email changes and clear stale OpenAI web state so the UI can't show the wrong user.
    /// This does not delete other per-email WebKit cookie stores (we keep multiple accounts around).
    func handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: String?) {
        let normalized = targetEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let normalized, !normalized.isEmpty else { return }

        let previous = store.lastOpenAIDashboardTargetEmail
        store.lastOpenAIDashboardTargetEmail = normalized

        if let previous,
           !previous.isEmpty,
           previous != normalized
        {
            let stamp = Date().formatted(date: .abbreviated, time: .shortened)
            self.logOpenAIWeb(
                "[\(stamp)] Codex account changed: \(previous) → \(normalized); " +
                    "clearing OpenAI web snapshot")
            store.openAIWebAccountDidChange = true
            store.openAIDashboard = nil
            store.openAIDashboardAttachmentAuthorized = false
            store.lastOpenAIDashboardSnapshot = nil
            store.lastOpenAIDashboardAttachmentAuthorized = false
            store.lastOpenAIDashboardError = nil
            store.lastOpenAIDashboardAttemptAt = nil
            store.openAIDashboardRequiresLogin = true
            store.openAIDashboardCookieImportStatus = "Codex account changed; importing browser cookies…"
            store.lastOpenAIDashboardCookieImportAttemptAt = nil
            store.lastOpenAIDashboardCookieImportEmail = nil
        }
    }

    func importOpenAIDashboardBrowserCookiesNow() async {
        self.resetOpenAIWebDebugLog(context: "manual import")
        let targetEmail = self.currentCodexOpenAIWebTargetEmail(
            allowCurrentSnapshotFallback: true,
            allowLastKnownLiveFallback: false)
        _ = await self.importOpenAIDashboardCookiesIfNeeded(targetEmail: targetEmail, force: true)
        let expectedGuard = store.currentCodexOpenAIWebRefreshGuard()
        await self.refreshOpenAIDashboardIfNeeded(
            force: true,
            expectedGuard: expectedGuard,
            bypassCoalescing: true)
    }

    func currentCodexOpenAIWebTargetEmail(
        allowCurrentSnapshotFallback: Bool,
        allowLastKnownLiveFallback: Bool) -> String?
    {
        switch store.settings.codexResolvedActiveSource {
        case .liveSystem:
            let liveSystem = store.settings.codexAccountReconciliationSnapshot.liveSystemAccount?.email
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let liveSystem, !liveSystem.isEmpty {
                store.lastKnownLiveSystemCodexEmail = liveSystem
                return liveSystem
            }

            if allowCurrentSnapshotFallback,
               let snapshotEmail = store.snapshots[.codex]?.accountEmail(for: .codex)?
                   .trimmingCharacters(in: .whitespacesAndNewlines),
                   !snapshotEmail.isEmpty
            {
                store.lastKnownLiveSystemCodexEmail = snapshotEmail
                return snapshotEmail
            }

            if allowLastKnownLiveFallback {
                let lastKnown = store.lastKnownLiveSystemCodexEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let lastKnown, !lastKnown.isEmpty { return lastKnown }
            }
            return nil
        case .managedAccount:
            return self.codexAccountEmailForOpenAIDashboard()
        }
    }

    private func openAIDashboardRefreshKey(
        targetEmail: String?,
        expectedGuard: CodexAccountScopedRefreshGuard?) -> String
    {
        let source = String(describing: expectedGuard?.source ?? store.settings.codexResolvedActiveSource)
        let identityKey = UsageStore.codexIdentityGuardKey(expectedGuard?.identity ?? .unresolved) ?? "unresolved"
        let accountKey = UsageStore.normalizeCodexAccountScopedKey(targetEmail) ?? "unknown"
        return "\(source)|\(identityKey)|\(accountKey)"
    }

    private func actionableOpenAIDashboardImportFailure(targetEmail: String?) -> String? {
        self.actionableOpenAIDashboardImportFailure(
            targetEmail: targetEmail,
            cookieImportStatus: store.openAIDashboardCookieImportStatus)
    }

    private func actionableOpenAIDashboardImportFailure(
        targetEmail: String?,
        cookieImportStatus: String?) -> String?
    {
        let status = cookieImportStatus?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let status, !status.isEmpty else { return nil }

        if status.localizedCaseInsensitiveContains("openai cookies are for") {
            return "\(status) Switch chatgpt.com account, then refresh OpenAI cookies."
        }
        if status.localizedCaseInsensitiveContains("no signed-in openai web session found") {
            let targetLabel = targetEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountLabel = (targetLabel?.isEmpty == false) ? targetLabel! : "your OpenAI account"
            return "\(status) Sign in to chatgpt.com as \(accountLabel), then refresh OpenAI cookies."
        }
        if status.localizedCaseInsensitiveContains("openai cookie import failed")
            || status.localizedCaseInsensitiveContains("browser cookie import failed")
        {
            return status
        }
        return nil
    }

    private func preferredOpenAIDashboardFailureMessage(
        error: Error,
        targetEmail: String?,
        cookieImportStatus: String?) -> String
    {
        if let actionable = self.actionableOpenAIDashboardImportFailure(
            targetEmail: targetEmail,
            cookieImportStatus: cookieImportStatus)
        {
            return actionable
        }
        return error.localizedDescription
    }

    private func abortOpenAIDashboardRetryAfterImportFailure(
        importedEmail: String?,
        targetEmail: String?,
        expectedGuard: CodexAccountScopedRefreshGuard?,
        cookieImportStatus: String?,
        refreshTaskToken: UUID) async -> Bool
    {
        guard importedEmail == nil,
              let message = self.actionableOpenAIDashboardImportFailure(
                  targetEmail: targetEmail,
                  cookieImportStatus: cookieImportStatus)
        else {
            return false
        }
        await self.applyOpenAIDashboardFailure(
            message: message,
            expectedGuard: expectedGuard,
            refreshTaskToken: refreshTaskToken,
            routingTargetEmail: targetEmail)
        return true
    }

    private func shouldApplyOpenAIDashboardRefreshTask(token: UUID?) -> Bool {
        guard let token else { return true }
        return store.openAIDashboardRefreshTaskToken == token
    }

    func invalidateOpenAIDashboardRefreshTask() {
        store.openAIDashboardRefreshTask?.cancel()
        store.openAIDashboardRefreshTask = nil
        store.openAIDashboardRefreshTaskKey = nil
        store.openAIDashboardRefreshTaskToken = nil
    }

    private func currentOpenAIDashboardCookieImportStatus() -> String? {
        store.openAIDashboardCookieImportStatus
    }

    private func loadLatestOpenAIDashboard(
        accountEmail: String?,
        logger: @escaping (String) -> Void,
        timeout: TimeInterval) async throws -> OpenAIDashboardSnapshot
    {
        if let override = store._test_openAIDashboardLoaderOverride {
            return try await override(accountEmail, logger, false, timeout)
        }
        return try await OpenAIDashboardFetcher().loadLatestDashboard(
            accountEmail: accountEmail,
            logger: logger,
            debugDumpHTML: timeout != OpenAIWebStore.dashboardFetchTimeout(didImportCookies: false),
            timeout: timeout)
    }

    private func failClosedForUnreadableManagedCodexStore() async -> String? {
        self.applyOpenAIDashboardCleanup(Set(CodexDashboardCleanup.allCases), preserveVisibleDashboard: false)
        store.openAIDashboardRequiresLogin = true
        store.openAIDashboardCookieImportStatus = [
            "Managed Codex account data is unavailable.",
            "Fix the managed account store before importing OpenAI cookies.",
        ].joined(separator: " ")
        return nil
    }

    private func failClosedRefreshForUnreadableManagedCodexStore() async {
        self.applyOpenAIDashboardCleanup(Set(CodexDashboardCleanup.allCases), preserveVisibleDashboard: false)
        store.openAIDashboardRequiresLogin = true
        store.lastOpenAIDashboardError = [
            "Managed Codex account data is unavailable.",
            "Fix the managed account store before refreshing OpenAI web data.",
        ].joined(separator: " ")
    }

    private func failClosedForMissingManagedCodexTarget() async -> String? {
        self.applyOpenAIDashboardCleanup(Set(CodexDashboardCleanup.allCases), preserveVisibleDashboard: false)
        store.openAIDashboardRequiresLogin = true
        store.openAIDashboardCookieImportStatus = [
            "The selected managed Codex account is unavailable.",
            "Pick another Codex account before importing OpenAI cookies.",
        ].joined(separator: " ")
        return nil
    }

    private func failClosedRefreshForMissingManagedCodexTarget() async {
        self.applyOpenAIDashboardCleanup(Set(CodexDashboardCleanup.allCases), preserveVisibleDashboard: false)
        store.openAIDashboardRequiresLogin = true
        store.lastOpenAIDashboardError = [
            "The selected managed Codex account is unavailable.",
            "Pick another Codex account before refreshing OpenAI web data.",
        ].joined(separator: " ")
    }

    private func openAIWebCookieImportShouldFailClosed() async -> Bool {
        if self.openAIWebManagedTargetStoreIsUnreadable() {
            _ = await self.failClosedForUnreadableManagedCodexStore()
            return true
        }
        if self.openAIWebManagedTargetIsMissing() {
            _ = await self.failClosedForMissingManagedCodexTarget()
            return true
        }
        return false
    }

    func importOpenAIDashboardCookiesIfNeeded(
        targetEmail: String?,
        force: Bool,
        preferCachedCookieHeader: Bool? = nil) async -> String?
    {
        if await self.openAIWebCookieImportShouldFailClosed() {
            return nil
        }

        let normalizedTarget = targetEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowAnyAccount = normalizedTarget == nil || normalizedTarget?.isEmpty == true
        let cookieSource = store.settings.codexCookieSource
        let cacheScope = self.codexCookieCacheScopeForOpenAIWeb()

        let now = Date()
        let lastEmail = store.lastOpenAIDashboardCookieImportEmail
        let lastAttempt = store.lastOpenAIDashboardCookieImportAttemptAt ?? .distantPast

        let shouldAttempt: Bool = if force {
            true
        } else {
            if allowAnyAccount {
                now.timeIntervalSince(lastAttempt) > 300
            } else {
                store.openAIDashboardRequiresLogin &&
                    (
                        lastEmail?.lowercased() != normalizedTarget?.lowercased() || now
                            .timeIntervalSince(lastAttempt) > 300)
            }
        }

        guard shouldAttempt else { return normalizedTarget }
        store.lastOpenAIDashboardCookieImportEmail = normalizedTarget
        store.lastOpenAIDashboardCookieImportAttemptAt = now

        let stamp = now.formatted(date: .abbreviated, time: .shortened)
        let targetLabel = normalizedTarget ?? "unknown"
        self.logOpenAIWeb("[\(stamp)] import start (target=\(targetLabel))")

        do {
            let log: (String) -> Void = { [weak self] message in
                guard let self else { return }
                self.logOpenAIWeb(message)
            }

            let result: OpenAIDashboardBrowserCookieImporter.ImportResult
            if let override = store._test_openAIDashboardCookieImportOverride {
                result = try await override(normalizedTarget, allowAnyAccount, cookieSource, cacheScope, log)
            } else {
                let importer = OpenAIDashboardBrowserCookieImporter(browserDetection: store.browserDetection)
                switch cookieSource {
                case .manual:
                    store.settings.ensureCodexCookieLoaded()
                    // Manual OpenAI cookies still come from one provider-level setting. Auto-imported cookies are
                    // isolated per managed account, but a manual header is an explicit override owned by settings,
                    // so switching managed accounts does not currently swap it underneath the user.
                    let manualHeader = store.settings.codexCookieHeader
                    guard CookieHeaderNormalizer.normalize(manualHeader) != nil else {
                        throw OpenAIDashboardBrowserCookieImporter.ImportError.manualCookieHeaderInvalid
                    }
                    result = try await importer.importManualCookies(
                        cookieHeader: manualHeader,
                        intoAccountEmail: normalizedTarget,
                        allowAnyAccount: allowAnyAccount,
                        cacheScope: cacheScope,
                        logger: log)
                case .auto:
                    result = try await importer.importBestCookies(
                        intoAccountEmail: normalizedTarget,
                        allowAnyAccount: allowAnyAccount,
                        preferCachedCookieHeader: preferCachedCookieHeader ?? !force,
                        cacheScope: cacheScope,
                        logger: log)
                case .off:
                    result = OpenAIDashboardBrowserCookieImporter.ImportResult(
                        sourceLabel: "Off",
                        cookieCount: 0,
                        signedInEmail: normalizedTarget,
                        matchesCodexEmail: true)
                }
            }
            let effectiveEmail = result.signedInEmail?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
                ? result.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
                : normalizedTarget
            store.lastOpenAIDashboardCookieImportEmail = effectiveEmail ?? normalizedTarget
            await MainActor.run {
                let signed = result.signedInEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchText = result.matchesCodexEmail ? "matches Codex" : "does not match Codex"
                let sourceLabel = switch cookieSource {
                case .manual:
                    "Manual cookie header"
                case .auto:
                    "\(result.sourceLabel) cookies"
                case .off:
                    "OpenAI cookies disabled"
                }
                if let signed, !signed.isEmpty {
                    store.openAIDashboardCookieImportStatus =
                        allowAnyAccount
                            ? [
                                "Using \(sourceLabel) (\(result.cookieCount)).",
                                "Signed in as \(signed).",
                            ].joined(separator: " ")
                            : [
                                "Using \(sourceLabel) (\(result.cookieCount)).",
                                "Signed in as \(signed) (\(matchText)).",
                            ].joined(separator: " ")
                } else {
                    store.openAIDashboardCookieImportStatus =
                        "Using \(sourceLabel) (\(result.cookieCount))."
                }
            }
            return effectiveEmail
        } catch let err as OpenAIDashboardBrowserCookieImporter.ImportError {
            switch err {
            case let .noMatchingAccount(found):
                let foundText: String = if found.isEmpty {
                    "no signed-in session detected in \(store.codexBrowserCookieOrder.loginHint)"
                } else {
                    found
                        .sorted { lhs, rhs in
                            if lhs.sourceLabel == rhs.sourceLabel { return lhs.email < rhs.email }
                            return lhs.sourceLabel < rhs.sourceLabel
                        }
                        .map { "\($0.sourceLabel): \($0.email)" }
                        .joined(separator: " • ")
                }
                self.logOpenAIWeb("[\(stamp)] import mismatch: \(foundText)")
                await MainActor.run {
                    store.openAIDashboardCookieImportStatus = allowAnyAccount
                        ? [
                            "No signed-in OpenAI web session found.",
                            "Found \(foundText).",
                        ].joined(separator: " ")
                        : OpenAIWebStore.conciseCookieMismatchStatus(
                            found: found.map(\.email),
                            targetEmail: normalizedTarget)
                    self.failClosedOpenAIDashboardSnapshot()
                }
            case .noCookiesFound,
                 .browserAccessDenied,
                 .dashboardStillRequiresLogin,
                 .manualCookieHeaderInvalid:
                self.logOpenAIWeb("[\(stamp)] import failed: \(err.localizedDescription)")
                await MainActor.run {
                    store.openAIDashboardCookieImportStatus =
                        "OpenAI cookie import failed: \(err.localizedDescription)"
                    store.openAIDashboardRequiresLogin = true
                }
            }
        } catch {
            self.logOpenAIWeb("[\(stamp)] import failed: \(error.localizedDescription)")
            await MainActor.run {
                store.openAIDashboardCookieImportStatus =
                    "Browser cookie import failed: \(error.localizedDescription)"
            }
        }
        return nil
    }

    private func resetOpenAIWebDebugLog(context: String) {
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        store.openAIWebDebugLines.removeAll(keepingCapacity: true)
        store.openAIDashboardCookieImportDebugLog = nil
        self.logOpenAIWeb("[\(stamp)] OpenAI web \(context) start")
    }

    private func logOpenAIWeb(_ message: String) {
        let safeMessage = LogRedactor.redact(message)
        store.openAIWebLogger.debug(safeMessage)
        store.openAIWebDebugLines.append(safeMessage)
        if store.openAIWebDebugLines.count > 240 {
            store.openAIWebDebugLines.removeFirst(store.openAIWebDebugLines.count - 240)
        }
        store.openAIDashboardCookieImportDebugLog = store.openAIWebDebugLines.joined(separator: "\n")
    }

    func resetOpenAIWebState() {
        self.invalidateOpenAIDashboardRefreshTask()
        OpenAIDashboardFetcher.evictAllCachedWebViews()
        store.openAIDashboard = nil
        store.openAIDashboardAttachmentAuthorized = false
        store.lastOpenAIDashboardError = nil
        store.lastOpenAIDashboardSnapshot = nil
        store.lastOpenAIDashboardAttachmentAuthorized = false
        store.lastOpenAIDashboardTargetEmail = nil
        store.lastOpenAIDashboardAttemptAt = nil
        store.openAIDashboardRequiresLogin = false
        store.openAIDashboardCookieImportStatus = nil
        store.openAIDashboardCookieImportDebugLog = nil
        store.lastOpenAIDashboardCookieImportAttemptAt = nil
        store.lastOpenAIDashboardCookieImportEmail = nil
        store.lastKnownLiveSystemCodexEmail = nil
    }

    /// Routing-only optimization: this detects whether the fetched browser session appears to be for a
    /// different account than the route target, so we can retry after cookie import. Ownership proof
    /// happens exclusively through CodexDashboardAuthority.
    private func dashboardEmailMismatch(expected: String?, actual: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return false }
        guard let raw = actual?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return false }
        return raw.lowercased() != expected.lowercased()
    }

    private func openAIWebManagedTargetStoreIsUnreadable() -> Bool {
        guard case .managedAccount = store.settings.codexResolvedActiveSource else {
            return false
        }
        return store.settings.codexSettingsSnapshot(tokenOverride: nil).managedAccountStoreUnreadable
    }

    private func openAIWebManagedTargetIsMissing() -> Bool {
        guard case .managedAccount = store.settings.codexResolvedActiveSource else {
            return false
        }
        return self.selectedManagedCodexAccountForOpenAIWeb() == nil
    }

    private func selectedManagedCodexAccountForOpenAIWeb() -> ManagedCodexAccount? {
        guard case let .managedAccount(id) = store.settings.codexResolvedActiveSource else {
            return nil
        }

        let snapshot = store.settings.codexAccountReconciliationSnapshot
        return snapshot.storedAccounts.first { $0.id == id }
    }

    func codexAccountEmailForOpenAIDashboard(allowLastKnownLiveFallback: Bool = true) -> String? {
        switch store.settings.codexResolvedActiveSource {
        case .liveSystem:
            let liveSystem = store.settings.codexAccountReconciliationSnapshot.liveSystemAccount?.email
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let liveSystem, !liveSystem.isEmpty {
                store.lastKnownLiveSystemCodexEmail = liveSystem
                return liveSystem
            }

            guard allowLastKnownLiveFallback else { return nil }
            let lastKnown = store.lastKnownLiveSystemCodexEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lastKnown, !lastKnown.isEmpty { return lastKnown }
            return nil
        case .managedAccount:
            if self.openAIWebManagedTargetStoreIsUnreadable() {
                return nil
            }

            let managed = store.currentManagedCodexRuntimeEmail()?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let managed, !managed.isEmpty { return managed }
            return nil
        }
    }

    func codexCookieCacheScopeForOpenAIWeb() -> CookieHeaderCache.Scope? {
        switch store.settings.codexResolvedActiveSource {
        case .liveSystem:
            nil
        case let .managedAccount(id):
            self.openAIWebManagedTargetStoreIsUnreadable() ? .managedStoreUnreadable : .managedAccount(id)
        }
    }

    func syncOpenAIWebState() {
        guard store.isEnabled(.codex),
              store.settings.openAIWebAccessEnabled,
              store.settings.codexCookieSource.isEnabled
        else {
            self.resetOpenAIWebState()
            return
        }

        let targetEmail = self.currentCodexOpenAIWebTargetEmail(
            allowCurrentSnapshotFallback: true,
            allowLastKnownLiveFallback: true)
        self.handleOpenAIWebTargetEmailChangeIfNeeded(targetEmail: targetEmail)
    }

}
