import AppKit
import CodexBarCore
import Foundation
import Observation
import SweetCookieKit

// MARK: - Observation helpers

@MainActor
extension UsageStore {
    var menuObservationToken: Int {
        _ = self.snapshots
        _ = self.errors
        _ = self.lastSourceLabels
        _ = self.lastFetchAttempts
        _ = self.accountSnapshots
        _ = self.tokenSnapshots
        _ = self.tokenErrors
        _ = self.tokenRefreshInFlight
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.versions
        _ = self.isRefreshing
        _ = self.refreshingProviders
        _ = self.pathDebugInfo
        _ = self.statuses
        _ = self.probeLogs
        _ = self.historicalPaceRevision
        return 0
    }

    var iconObservationToken: Int {
        _ = self.snapshots
        _ = self.errors
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.isRefreshing
        _ = self.refreshingProviders
        _ = self.statuses
        _ = self.historicalPaceRevision
        return 0
    }

    func observeSettingsChanges() {
        withObservationTracking {
            _ = self.settings.refreshFrequency
            _ = self.settings.statusChecksEnabled
            _ = self.settings.sessionQuotaNotificationsEnabled
            _ = self.settings.usageBarsShowUsed
            _ = self.settings.costUsageEnabled
            _ = self.settings.randomBlinkEnabled
            _ = self.settings.configRevision
            for implementation in ProviderCatalog.all {
                implementation.observeSettings(self.settings)
            }
            _ = self.settings.showAllTokenAccountsInMenu
            _ = self.settings.tokenAccountsByProvider
            _ = self.settings.mergeIcons
            _ = self.settings.selectedMenuProvider
            _ = self.settings.debugLoadingPattern
            _ = self.settings.debugKeepCLISessionsAlive
            _ = self.settings.historicalTrackingEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeSettingsChanges()
                self.probeLogs = [:]
                guard self.startupBehavior.automaticallyStartsBackgroundWork else { return }
                self.startTimer()
                self.updateProviderRuntimes()
                await self.refreshHistoricalDatasetIfNeeded()
                await self.refresh()
            }
        }
    }

    var attachedOpenAIDashboardSnapshot: OpenAIDashboardSnapshot? {
        guard self.openAIDashboardAttachmentAuthorized else { return nil }
        return self.openAIDashboard
    }
}

@MainActor
@Observable
final class UsageStore {
    enum CodexCreditsSource {
        case none
        case api
        case dashboardWeb
    }

    enum StartupBehavior {
        case automatic
        case full
        case testing

        var automaticallyStartsBackgroundWork: Bool {
            switch self {
            case .automatic, .full:
                true
            case .testing:
                false
            }
        }

        func resolved(isRunningTests: Bool) -> StartupBehavior {
            switch self {
            case .automatic:
                isRunningTests ? .testing : .full
            case .full, .testing:
                self
            }
        }
    }

    var snapshots: [UsageProvider: UsageSnapshot] = [:]
    var errors: [UsageProvider: String] = [:]
    var lastSourceLabels: [UsageProvider: String] = [:]
    var lastFetchAttempts: [UsageProvider: [ProviderFetchAttempt]] = [:]
    var accountSnapshots: [UsageProvider: [TokenAccountUsageSnapshot]] = [:]
    var tokenSnapshots: [UsageProvider: CostUsageTokenSnapshot] = [:]
    var tokenErrors: [UsageProvider: String] = [:]
    var tokenRefreshInFlight: Set<UsageProvider> = []
    var credits: CreditsSnapshot?
    var lastCreditsError: String?
    var openAIDashboard: OpenAIDashboardSnapshot?
    var lastOpenAIDashboardError: String?
    var openAIDashboardRequiresLogin: Bool = false
    var openAIDashboardCookieImportStatus: String?
    var openAIDashboardCookieImportDebugLog: String?
    var versions: [UsageProvider: String] = [:]
    var isRefreshing = false
    var refreshingProviders: Set<UsageProvider> = []
    var debugForceAnimation = false
    var pathDebugInfo: PathDebugSnapshot = .empty
    var statuses: [UsageProvider: ProviderStatus] = [:]
    var probeLogs: [UsageProvider: String] = [:]
    var historicalPaceRevision: Int = 0
    @ObservationIgnored var lastCreditsSnapshot: CreditsSnapshot?
    @ObservationIgnored var lastCreditsSnapshotAccountKey: String?
    @ObservationIgnored var lastCreditsSource: CodexCreditsSource = .none
    @ObservationIgnored var creditsFailureStreak: Int = 0
    @ObservationIgnored var openAIDashboardAttachmentAuthorized: Bool = false
    @ObservationIgnored var lastOpenAIDashboardSnapshot: OpenAIDashboardSnapshot?
    @ObservationIgnored var lastOpenAIDashboardAttachmentAuthorized: Bool = false
    @ObservationIgnored var lastOpenAIDashboardTargetEmail: String?
    @ObservationIgnored var lastOpenAIDashboardAttemptAt: Date?
    @ObservationIgnored var lastOpenAIDashboardCookieImportAttemptAt: Date?
    @ObservationIgnored var lastOpenAIDashboardCookieImportEmail: String?
    @ObservationIgnored var lastCodexAccountScopedRefreshGuard: CodexAccountScopedRefreshGuard?
    @ObservationIgnored var lastKnownLiveSystemCodexEmail: String?
    @ObservationIgnored var openAIWebAccountDidChange: Bool = false
    @ObservationIgnored var openAIDashboardRefreshTask: Task<Void, Never>?
    @ObservationIgnored var openAIDashboardRefreshTaskKey: String?
    @ObservationIgnored var openAIDashboardRefreshTaskToken: UUID?
    @ObservationIgnored var _test_openAIDashboardCookieImportOverride: (@MainActor (
        String?,
        Bool,
        ProviderCookieSource,
        CookieHeaderCache.Scope?,
        @escaping (String) -> Void) async throws -> OpenAIDashboardBrowserCookieImporter.ImportResult)?
    @ObservationIgnored var _test_openAIDashboardLoaderOverride: (@MainActor (
        String?,
        @escaping (String) -> Void,
        TimeInterval) async throws -> OpenAIDashboardSnapshot)?
    @ObservationIgnored var _test_codexCreditsLoaderOverride: (@MainActor () async throws -> CreditsSnapshot)?
    @ObservationIgnored var _test_widgetSnapshotSaveOverride: (@MainActor (WidgetSnapshot) async -> Void)?
    @ObservationIgnored var widgetSnapshotPersistTask: Task<Void, Never>?

    @ObservationIgnored let codexFetcher: UsageFetcher
    @ObservationIgnored let claudeFetcher: any ClaudeUsageFetching
    @ObservationIgnored private let costUsageFetcher: CostUsageFetcher
    @ObservationIgnored let browserDetection: BrowserDetection
    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let environmentBase: [String: String]
    @ObservationIgnored private let sessionQuotaNotifier: any SessionQuotaNotifying
    @ObservationIgnored let quotaWarningNotifier = QuotaWarningNotifier()
    @ObservationIgnored private let sessionQuotaLogger = CodexBarLog.logger(LogCategories.sessionQuota)
    @ObservationIgnored var openAIWebStore: OpenAIWebStore!
    @ObservationIgnored var planUtilizationStore: PlanUtilizationStore!
    @ObservationIgnored var historicalPaceStore: HistoricalPaceStore!
    @ObservationIgnored var widgetSnapshotBuilder: WidgetSnapshotBuilder!
    @ObservationIgnored let openAIWebLogger = CodexBarLog.logger(LogCategories.openAIWeb)
    @ObservationIgnored private let tokenCostLogger = CodexBarLog.logger(LogCategories.tokenCost)
    @ObservationIgnored let augmentLogger = CodexBarLog.logger(LogCategories.augment)
    @ObservationIgnored let providerLogger = CodexBarLog.logger(LogCategories.providers)
    @ObservationIgnored var openAIWebDebugLines: [String] = []
    @ObservationIgnored var failureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    @ObservationIgnored var tokenFailureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    @ObservationIgnored var providerSpecs: [UsageProvider: ProviderSpec] = [:]
    @ObservationIgnored let providerMetadata: [UsageProvider: ProviderMetadata]
    @ObservationIgnored var providerRuntimes: [UsageProvider: any ProviderRuntime] = [:]
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var tokenTimerTask: Task<Void, Never>?
    @ObservationIgnored private var tokenRefreshSequenceTask: Task<Void, Never>?
    @ObservationIgnored private var pathDebugRefreshTask: Task<Void, Never>?
    @ObservationIgnored var codexPlanHistoryBackfillTask: Task<Void, Never>?
    @ObservationIgnored let historicalUsageHistoryStore: HistoricalUsageHistoryStore
    @ObservationIgnored let planUtilizationHistoryStore: PlanUtilizationHistoryStore
    @ObservationIgnored var codexHistoricalDataset: CodexHistoricalDataset?
    @ObservationIgnored var codexHistoricalDatasetAccountKey: String?
    @ObservationIgnored var lastKnownSessionRemaining: [UsageProvider: Double] = [:]
    @ObservationIgnored var lastKnownSessionWindowSource: [UsageProvider: SessionQuotaWindowSource] = [:]
    @ObservationIgnored var lastTokenFetchAt: [UsageProvider: Date] = [:]
    @ObservationIgnored var planUtilizationHistory: [UsageProvider: PlanUtilizationHistoryBuckets] = [:]
    @ObservationIgnored var weeklyLimitResetDetectorStates: [String: PlanUtilizationStore.WeeklyLimitResetDetectorState] = [:]
    @ObservationIgnored private var hasCompletedInitialRefresh: Bool = false
    @ObservationIgnored private let tokenFetchTTL: TimeInterval = 60 * 60
    @ObservationIgnored private let tokenFetchTimeout: TimeInterval = 10 * 60
    @ObservationIgnored private let startupBehavior: StartupBehavior
    @ObservationIgnored let planUtilizationPersistenceCoordinator: PlanUtilizationHistoryPersistenceCoordinator

    init(
        fetcher: UsageFetcher,
        browserDetection: BrowserDetection,
        claudeFetcher: (any ClaudeUsageFetching)? = nil,
        costUsageFetcher: CostUsageFetcher = CostUsageFetcher(),
        settings: SettingsStore,
        registry: ProviderRegistry = .shared,
        historicalUsageHistoryStore: HistoricalUsageHistoryStore = HistoricalUsageHistoryStore(),
        planUtilizationHistoryStore: PlanUtilizationHistoryStore = .defaultAppSupport(),
        sessionQuotaNotifier: any SessionQuotaNotifying = SessionQuotaNotifier(),
        startupBehavior: StartupBehavior = .automatic,
        environmentBase: [String: String] = ProcessInfo.processInfo.environment)
    {
        self.codexFetcher = fetcher
        self.browserDetection = browserDetection
        self.claudeFetcher = claudeFetcher ?? ClaudeUsageFetcher(browserDetection: browserDetection)
        self.costUsageFetcher = costUsageFetcher
        self.settings = settings
        self.registry = registry
        self.environmentBase = environmentBase
        self.historicalUsageHistoryStore = historicalUsageHistoryStore
        self.planUtilizationHistoryStore = planUtilizationHistoryStore
        self.sessionQuotaNotifier = sessionQuotaNotifier
        self.startupBehavior = startupBehavior.resolved(isRunningTests: Self.isRunningTestsProcess())
        self.planUtilizationPersistenceCoordinator = PlanUtilizationHistoryPersistenceCoordinator(
            store: planUtilizationHistoryStore)
        self.providerMetadata = registry.metadata
        self
            .failureGates = Dictionary(
                uniqueKeysWithValues: UsageProvider.allCases
                    .map { ($0, ConsecutiveFailureGate()) })
        self.tokenFailureGates = Dictionary(
            uniqueKeysWithValues: UsageProvider.allCases
                .map { ($0, ConsecutiveFailureGate()) })
        self.providerSpecs = registry.specs(
            settings: settings,
            metadata: self.providerMetadata,
            codexFetcher: fetcher,
            claudeFetcher: self.claudeFetcher,
            browserDetection: browserDetection,
            environmentBase: environmentBase)
        self.providerRuntimes = Dictionary(uniqueKeysWithValues: ProviderCatalog.all.compactMap { implementation in
            implementation.makeRuntime().map { (implementation.id, $0) }
        })
        self.planUtilizationHistory = planUtilizationHistoryStore.load()
        self.weeklyLimitResetDetectorStates = Self.loadWeeklyLimitResetDetectorStates(from: settings.userDefaults)
        self.openAIWebStore = OpenAIWebStore(store: self)
        self.planUtilizationStore = PlanUtilizationStore(store: self)
        self.historicalPaceStore = HistoricalPaceStore(store: self)
        self.widgetSnapshotBuilder = WidgetSnapshotBuilder(store: self)
        self.logStartupState()
        self.bindSettings()
        self.pathDebugInfo = PathDebugSnapshot(
            codexBinary: nil,
            claudeBinary: nil,
            geminiBinary: nil,
            effectivePATH: PathBuilder.effectivePATH(purposes: [.rpc, .tty, .nodeTooling]),
            loginShellPATH: LoginShellPathCache.shared.current?.joined(separator: ":"))
        guard self.startupBehavior.automaticallyStartsBackgroundWork else { return }
        self.detectVersions()
        self.updateProviderRuntimes()
        Task { @MainActor [weak self] in
            self?.schedulePathDebugInfoRefresh()
        }
        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.schedulePathDebugInfoRefresh()
            }
        }
        Task { @MainActor [weak self] in
            await self?.refreshHistoricalDatasetIfNeeded()
        }
        Task { await self.refresh() }
        self.startTimer()
        self.startTokenTimer()
    }

    private static func isRunningTestsProcess() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        if environment["SWIFT_TESTING_ENABLED"] != nil { return true }
        return CommandLine.arguments.contains { argument in
            argument.contains("xctest") || argument.contains("swift-testing")
        }
    }

    /// Returns the login method (plan type) for the specified provider, if available.
    private func loginMethod(for provider: UsageProvider) -> String? {
        self.snapshots[provider]?.loginMethod(for: provider)
    }

    /// Returns true if the Claude account appears to be a subscription (Max, Pro, Ultra, Team).
    /// Returns false for API users or when plan cannot be determined.
    func isClaudeSubscription() -> Bool {
        Self.isSubscriptionPlan(self.loginMethod(for: .claude))
    }

    /// Determines if a login method string indicates a Claude subscription plan.
    /// Known subscription indicators: Max, Pro, Ultra, Team (case-insensitive).
    nonisolated static func isSubscriptionPlan(_ loginMethod: String?) -> Bool {
        ClaudePlan.isSubscriptionLoginMethod(loginMethod)
    }

    func version(for provider: UsageProvider) -> String? {
        self.versions[provider]
    }

    var preferredSnapshot: UsageSnapshot? {
        for provider in self.enabledProviders() {
            if let snap = self.snapshots[provider] { return snap }
        }
        return nil
    }

    var iconStyle: IconStyle {
        let enabled = self.enabledProviders()
        if enabled.count > 1 { return .combined }
        if let provider = enabled.first {
            return self.style(for: provider)
        }
        return .codex
    }

    var isStale: Bool {
        for provider in self.enabledProviders() where self.errors[provider] != nil {
            return true
        }
        return false
    }

    func enabledProviders() -> [UsageProvider] {
        // Use cached enablement to avoid repeated UserDefaults lookups in animation ticks.
        let enabled = self.settings.enabledProvidersOrdered(metadataByProvider: self.providerMetadata)
        return enabled.filter { self.isProviderAvailable($0) }
    }

    /// Enabled providers without availability filtering. Used for display (switcher, merge-icons).
    func enabledProvidersForDisplay() -> [UsageProvider] {
        self.settings.enabledProvidersOrdered(metadataByProvider: self.providerMetadata)
    }

    /// Providers that should actually participate in background refresh/status/token work.
    func enabledProvidersForBackgroundWork() -> [UsageProvider] {
        self.enabledProviders()
    }

    var statusChecksEnabled: Bool {
        self.settings.statusChecksEnabled
    }

    func metadata(for provider: UsageProvider) -> ProviderMetadata {
        guard let meta = self.providerMetadata[provider] else {
            let fallback = ProviderMetadata(
                id: provider,
                displayName: provider.rawValue,
                sessionLabel: provider.rawValue,
                weeklyLabel: provider.rawValue,
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: provider.rawValue,
                cliName: provider.rawValue,
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: nil,
                subscriptionDashboardURL: nil,
                statusPageURL: nil,
                statusLinkURL: nil,
                statusWorkspaceProductID: nil)
            CodexBarLog.logger(LogCategories.providers)
                .error("Missing ProviderMetadata for \(provider.rawValue); using fallback. Was providerMetadata initialized before access?")
            assertionFailure("Missing metadata entry for \(provider.rawValue); check initialization order.")
            return fallback
        }
        return meta
    }

    var codexBrowserCookieOrder: BrowserCookieImportOrder {
        self.metadata(for: .codex).browserCookieOrder ?? Browser.defaultImportOrder
    }

    func snapshot(for provider: UsageProvider) -> UsageSnapshot? {
        self.snapshots[provider]
    }

    func sourceLabel(for provider: UsageProvider) -> String {
        var label = self.lastSourceLabels[provider] ?? ""
        if label.isEmpty {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let modes = descriptor.fetchPlan.sourceModes
            if modes.count == 1, let mode = modes.first {
                label = mode.rawValue
            } else {
                let context = ProviderSourceLabelContext(
                    provider: provider,
                    settings: self.settings,
                    store: self,
                    descriptor: descriptor)
                label = ProviderCatalog.implementation(for: provider)?
                    .defaultSourceLabel(context: context)
                    ?? "auto"
            }
        }

        let context = ProviderSourceLabelContext(
            provider: provider,
            settings: self.settings,
            store: self,
            descriptor: ProviderDescriptorRegistry.descriptor(for: provider))
        return ProviderCatalog.implementation(for: provider)?
            .decorateSourceLabel(context: context, baseLabel: label)
            ?? label
    }

    func fetchAttempts(for provider: UsageProvider) -> [ProviderFetchAttempt] {
        self.lastFetchAttempts[provider] ?? []
    }

    func style(for provider: UsageProvider) -> IconStyle {
        self.providerSpecs[provider]?.style ?? .codex
    }

    func isStale(provider: UsageProvider) -> Bool {
        self.errors[provider] != nil
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        let enabled = self.settings.isProviderEnabledCached(
            provider: provider,
            metadataByProvider: self.providerMetadata)
        guard enabled else { return false }
        return self.isProviderAvailable(provider)
    }

    func isProviderAvailable(_ provider: UsageProvider) -> Bool {
        // Availability should mirror the effective fetch environment, including token-account overrides.
        // Otherwise providers (notably token-account-backed API providers) can fetch successfully but be
        // hidden from the menu because their credentials are not in ProcessInfo's environment.
        let environment = ProviderRegistry.makeEnvironment(
            base: self.environmentBase,
            provider: provider,
            settings: self.settings,
            tokenOverride: nil)
        let context = ProviderAvailabilityContext(
            provider: provider,
            settings: self.settings,
            environment: environment)
        return ProviderCatalog.implementation(for: provider)?
            .isAvailable(context: context)
            ?? true
    }

    func performRuntimeAction(_ action: ProviderRuntimeAction, for provider: UsageProvider) async {
        guard let runtime = self.providerRuntimes[provider] else { return }
        let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
        await runtime.perform(action: action, context: context)
    }

    private func updateProviderRuntimes() {
        for (provider, runtime) in self.providerRuntimes {
            let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
            if self.isEnabled(provider) {
                runtime.start(context: context)
            } else {
                runtime.stop(context: context)
            }
            runtime.settingsDidChange(context: context)
        }
    }

    func refresh(forceTokenUsage: Bool = false) async {
        guard !self.isRefreshing else { return }
        self.prepareRefreshState()
        let refreshPhase: ProviderRefreshPhase = self.hasCompletedInitialRefresh ? .regular : .startup
        let displayEnabledProviders = self.enabledProvidersForDisplay()
        let enabledProviderSet = Set(displayEnabledProviders)
        let refreshProviders = self.enabledProvidersForBackgroundWork()
        let availableRefreshProviders = Set(self.enabledProviders())
        let refreshStartedAt = Date()

        await ProviderRefreshContext.$current.withValue(refreshPhase) {
            self.isRefreshing = true
            defer {
                self.isRefreshing = false
                self.hasCompletedInitialRefresh = true
            }

            self.clearDisabledProviderState(enabledProviders: enabledProviderSet)
            self.clearUnavailableProviderState(
                displayEnabledProviders: enabledProviderSet,
                availableProviders: availableRefreshProviders)

            await withTaskGroup(of: Void.self) { group in
                for provider in refreshProviders {
                    group.addTask { await self.refreshProvider(provider) }
                    if availableRefreshProviders.contains(provider) {
                        group.addTask { await self.refreshStatus(provider) }
                    }
                }
                group.addTask { await self.refreshCreditsIfNeeded(minimumSnapshotUpdatedAt: refreshStartedAt) }
            }

            // Token-cost usage can be slow; run it outside the refresh group so we don't block menu updates.
            self.scheduleTokenRefresh(force: forceTokenUsage)

            // OpenAI web scrape depends on the current Codex account email (which can change after login/account
            // switch). Run this after Codex usage refresh so we don't accidentally scrape with stale credentials.
            self.syncOpenAIWebState()
            let refreshPolicy = OpenAIWebStore.RefreshPolicyContext(
                accessEnabled: self.isEnabled(.codex) &&
                    self.settings.openAIWebAccessEnabled &&
                    self.settings.codexCookieSource.isEnabled,
                batterySaverEnabled: self.settings.openAIWebBatterySaverEnabled,
                force: forceTokenUsage)
            let shouldRefreshOpenAIWeb = OpenAIWebStore.shouldRunRefresh(refreshPolicy)
            self.openAIWebLogger.debug(
                "OpenAI web refresh gate",
                metadata: [
                    "allowed": shouldRefreshOpenAIWeb ? "1" : "0",
                    "accessEnabled": refreshPolicy.accessEnabled ? "1" : "0",
                    "batterySaverEnabled": refreshPolicy.batterySaverEnabled ? "1" : "0",
                    "force": refreshPolicy.force ? "1" : "0",
                    "interaction": ProviderInteractionContext.current == .userInitiated ? "user" : "background",
                    "phase": refreshPhase == .startup ? "startup" : "regular",
                ])
            if shouldRefreshOpenAIWeb {
                let codexDashboardGuard = self.currentCodexOpenAIWebRefreshGuard()
                await self.refreshOpenAIDashboardIfNeeded(
                    force: forceTokenUsage,
                    expectedGuard: codexDashboardGuard)
            }

            if forceTokenUsage, self.openAIDashboardRequiresLogin {
                await self.refreshProvider(.codex)
                await self.refreshCreditsIfNeeded(minimumSnapshotUpdatedAt: refreshStartedAt)
            }

            self.persistWidgetSnapshot(reason: "refresh")
        }
    }

    /// For demo/testing: drop the snapshot so the loading animation plays, then restore the last snapshot.
    func replayLoadingAnimation(duration: TimeInterval = 3) {
        let current = self.preferredSnapshot
        self.snapshots.removeAll()
        self.debugForceAnimation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if let current, let provider = self.enabledProviders().first {
                self.snapshots[provider] = current
            }
            self.debugForceAnimation = false
        }
    }

    // MARK: - Private

    private func bindSettings() {
        self.observeSettingsChanges()
    }

    private func startTimer() {
        self.timerTask?.cancel()
        guard let wait = self.settings.refreshFrequency.seconds else { return }

        // Background poller so the menu stays responsive; canceled when settings change or store deallocates.
        self.timerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                await self?.refresh()
            }
        }
    }

    private func startTokenTimer() {
        self.tokenTimerTask?.cancel()
        let wait = self.tokenFetchTTL
        self.tokenTimerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                await self?.scheduleTokenRefresh(force: false)
            }
        }
    }

    private func scheduleTokenRefresh(force: Bool) {
        if force {
            self.tokenRefreshSequenceTask?.cancel()
            self.tokenRefreshSequenceTask = nil
        } else if self.tokenRefreshSequenceTask != nil {
            return
        }

        let providers = self.enabledProvidersForBackgroundWork()
        self.tokenRefreshSequenceTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.tokenRefreshSequenceTask = nil
                }
            }
            for provider in providers {
                if Task.isCancelled { break }
                await self.refreshTokenUsage(provider, force: force)
            }
        }
    }

    deinit {
        self.timerTask?.cancel()
        self.tokenTimerTask?.cancel()
        self.tokenRefreshSequenceTask?.cancel()
        self.codexPlanHistoryBackfillTask?.cancel()
    }

    enum SessionQuotaWindowSource: String {
        case primary
        case copilotSecondaryFallback
    }

    private func sessionQuotaWindow(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> (window: RateWindow, source: SessionQuotaWindowSource)?
    {
        if let primary = snapshot.primary, Self.isSessionWindow(primary) {
            return (primary, .primary)
        }
        if provider == .copilot, let secondary = snapshot.secondary {
            return (secondary, .copilotSecondaryFallback)
        }
        return nil
    }

    private static func isSessionWindow(_ window: RateWindow) -> Bool {
        guard let minutes = window.windowMinutes else { return true }
        return minutes <= 6 * 60
    }

    func handleSessionQuotaTransition(provider: UsageProvider, snapshot: UsageSnapshot) {
        // Session quota notifications are tied to the primary session window. Copilot free plans can
        // expose only chat quota, so allow Copilot to fall back to secondary for transition tracking.
        guard let sessionWindow = self.sessionQuotaWindow(provider: provider, snapshot: snapshot) else {
            self.lastKnownSessionRemaining.removeValue(forKey: provider)
            self.lastKnownSessionWindowSource.removeValue(forKey: provider)
            return
        }
        let currentRemaining = sessionWindow.window.remainingPercent
        let currentSource = sessionWindow.source
        let previousRemaining = self.lastKnownSessionRemaining[provider]
        let previousSource = self.lastKnownSessionWindowSource[provider]

        if let previousSource, previousSource != currentSource {
            let providerText = provider.rawValue
            self.sessionQuotaLogger.debug(
                "session window source changed: provider=\(providerText) prevSource=\(previousSource.rawValue) " +
                    "currSource=\(currentSource.rawValue) curr=\(currentRemaining)")
            self.lastKnownSessionRemaining[provider] = currentRemaining
            self.lastKnownSessionWindowSource[provider] = currentSource
            return
        }

        defer {
            self.lastKnownSessionRemaining[provider] = currentRemaining
            self.lastKnownSessionWindowSource[provider] = currentSource
        }

        guard self.settings.sessionQuotaNotificationsEnabled else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let providerText = provider.rawValue
                let message =
                    "notifications disabled: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
                self.sessionQuotaLogger.debug(message)
            }
            return
        }

        guard previousRemaining != nil else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) {
                let providerText = provider.rawValue
                let message = "startup depleted: provider=\(providerText) curr=\(currentRemaining)"
                self.sessionQuotaLogger.info(message)
                self.sessionQuotaNotifier.post(transition: .depleted, provider: provider, badge: nil)
            }
            return
        }

        let transition = SessionQuotaNotificationLogic.transition(
            previousRemaining: previousRemaining,
            currentRemaining: currentRemaining)
        guard transition != .none else {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let providerText = provider.rawValue
                let message =
                    "no transition: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
                self.sessionQuotaLogger.debug(message)
            }
            return
        }

        let providerText = provider.rawValue
        let transitionText = String(describing: transition)
        let message =
            "transition \(transitionText): provider=\(providerText) " +
            "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)"
        self.sessionQuotaLogger.info(message)

        self.sessionQuotaNotifier.post(transition: transition, provider: provider, badge: nil)
    }

    private func refreshStatus(_ provider: UsageProvider) async {
        guard self.settings.statusChecksEnabled else { return }
        guard let meta = self.providerMetadata[provider] else { return }

        do {
            let status: ProviderStatus
            if let urlString = meta.statusPageURL, let baseURL = URL(string: urlString) {
                status = try await StatusStore.fetchStatus(from: baseURL)
            } else if let productID = meta.statusWorkspaceProductID {
                status = try await StatusStore.fetchWorkspaceStatus(productID: productID)
            } else {
                return
            }
            await MainActor.run { self.statuses[provider] = status }
        } catch {
            // Keep the previous status to avoid flapping when the API hiccups.
            await MainActor.run {
                if self.statuses[provider] == nil {
                    self.statuses[provider] = ProviderStatus(
                        indicator: .unknown,
                        description: error.localizedDescription,
                        updatedAt: nil)
                }
            }
        }
    }
}

extension UsageStore {
    func debugDumpClaude() async {
        let fetcher = ClaudeUsageFetcher(
            browserDetection: self.browserDetection,
            keepCLISessionsAlive: self.settings.debugKeepCLISessionsAlive)
        let output = await fetcher.debugRawProbe(model: "sonnet")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codexbar-claude-probe.txt")
        try? output.write(to: url, atomically: true, encoding: .utf8)
        await MainActor.run {
            let snippet = String(output.prefix(180)).replacingOccurrences(of: "\n", with: " ")
            self.errors[.claude] = "[Claude] \(snippet) (saved: \(url.path))"
            NSWorkspace.shared.open(url)
        }
    }

    func dumpLog(toFileFor provider: UsageProvider) async -> URL? {
        let text = await self.debugLog(for: provider)
        let filename = "codexbar-\(provider.rawValue)-probe.txt"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
            return url
        } catch {
            await MainActor.run {
                self.errors[provider] = "Failed to save log: \(error.localizedDescription)"
            }
            return nil
        }
    }

    func debugAugmentDump() async -> String {
        await AugmentStatusProbe.latestDumps()
    }

    func debugLog(for provider: UsageProvider) async -> String {
        if let cached = self.probeLogs[provider], !cached.isEmpty {
            return cached
        }

        let claudeWebExtrasEnabled = self.settings.claudeWebExtrasEnabled
        let claudeUsageDataSource = self.settings.claudeUsageDataSource
        let claudeCookieSource = self.settings.claudeCookieSource
        let claudeCookieHeader = self.settings.claudeCookieHeader
        let claudeDebugConfiguration: ClaudeDebugLogConfiguration? = if provider == .claude {
            await self.makeClaudeDebugConfiguration(
                fallbackUsageDataSource: claudeUsageDataSource,
                fallbackWebExtrasEnabled: claudeWebExtrasEnabled,
                fallbackCookieSource: claudeCookieSource,
                fallbackCookieHeader: claudeCookieHeader)
        } else {
            nil
        }
        let cursorCookieSource = self.settings.cursorCookieSource
        let cursorCookieHeader = self.settings.cursorCookieHeader
        let kiloConfigToken = self.settings.providerConfig(for: .kilo)?.sanitizedAPIKey
        let ampCookieSource = self.settings.ampCookieSource
        let ampCookieHeader = self.settings.ampCookieHeader
        let ollamaCookieSource = self.settings.ollamaCookieSource
        let ollamaCookieHeader = self.settings.ollamaCookieHeader
        let processEnvironment = self.environmentBase
        let openRouterConfigToken = self.settings.providerConfig(for: .openrouter)?.sanitizedAPIKey
        let openRouterHasEnvToken = OpenRouterSettingsReader.apiToken(environment: processEnvironment) != nil
        let openRouterEnvironment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: processEnvironment,
            provider: .openrouter,
            config: self.settings.providerConfig(for: .openrouter))
        let deepSeekHasEnvToken = DeepSeekSettingsReader.apiKey(environment: processEnvironment) != nil
        let deepSeekHasTokenAccount = self.settings.selectedTokenAccount(for: .deepseek) != nil
        let deepSeekEnvironment = ProviderRegistry.makeEnvironment(
            base: processEnvironment,
            provider: .deepseek,
            settings: self.settings,
            tokenOverride: nil)
        let codexFetcher = self.codexFetcher
        let browserDetection = self.browserDetection
        let claudeDebugExecutionContext = self.currentClaudeDebugExecutionContext()
        let text = await Task.detached(priority: .utility) { () -> String in
            let buildText = {
                switch provider {
                case .codex:
                    return await codexFetcher.debugRawRateLimits()
                case .claude:
                    guard let claudeDebugConfiguration else {
                        return "Claude debug log configuration unavailable"
                    }
                    return await claudeDebugExecutionContext.apply {
                        await Self.debugClaudeLog(
                            browserDetection: browserDetection,
                            configuration: claudeDebugConfiguration)
                    }
                case .zai:
                    let resolution = ProviderTokenResolver.zaiResolution()
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "Z_AI_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
                case .synthetic:
                    let resolution = ProviderTokenResolver.syntheticResolution()
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "SYNTHETIC_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
                case .cursor:
                    return await Self.debugCursorLog(
                        browserDetection: browserDetection,
                        cursorCookieSource: cursorCookieSource,
                        cursorCookieHeader: cursorCookieHeader)
                case .minimax:
                    let tokenResolution = ProviderTokenResolver.minimaxTokenResolution()
                    let cookieResolution = ProviderTokenResolver.minimaxCookieResolution()
                    let tokenSource = tokenResolution?.source.rawValue ?? "none"
                    let cookieSource = cookieResolution?.source.rawValue ?? "none"
                    return "MINIMAX_API_KEY=\(tokenResolution == nil ? "missing" : "present") " +
                        "source=\(tokenSource) MINIMAX_COOKIE=\(cookieResolution == nil ? "missing" : "present") " +
                        "source=\(cookieSource)"
                case .alibaba:
                    let resolution = ProviderTokenResolver.alibabaTokenResolution()
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "ALIBABA_CODING_PLAN_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
                case .augment:
                    return await Self.debugAugmentLog()
                case .amp:
                    return await Self.debugAmpLog(
                        browserDetection: browserDetection,
                        ampCookieSource: ampCookieSource,
                        ampCookieHeader: ampCookieHeader)
                case .ollama:
                    return await Self.debugOllamaLog(
                        browserDetection: browserDetection,
                        ollamaCookieSource: ollamaCookieSource,
                        ollamaCookieHeader: ollamaCookieHeader)
                case .openrouter:
                    return Self.apiKeyDebugLine(
                        label: "OPENROUTER_API_KEY",
                        resolution: ProviderTokenResolver.openRouterResolution(environment: openRouterEnvironment),
                        configToken: openRouterConfigToken,
                        hasEnvToken: openRouterHasEnvToken)
                case .warp:
                    let resolution = ProviderTokenResolver.warpResolution()
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "WARP_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
                case .deepseek:
                    return Self.apiKeyDebugLine(
                        label: "DEEPSEEK_API_KEY",
                        resolution: ProviderTokenResolver.deepseekResolution(environment: deepSeekEnvironment),
                        configToken: nil,
                        hasEnvToken: deepSeekHasEnvToken,
                        hasTokenAccount: deepSeekHasTokenAccount)
                case .kilo:
                    let resolution = ProviderTokenResolver.kiloResolution(environment: processEnvironment)
                    return Self.apiKeyDebugLine(
                        label: "KILO_API_KEY",
                        resolution: resolution,
                        configToken: kiloConfigToken,
                        hasEnvToken: KiloSettingsReader.apiKey(environment: processEnvironment) != nil)
                case .kimi:
                    let resolution = ProviderTokenResolver.kimiAuthResolution(environment: processEnvironment)
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "KIMI_AUTH=\(hasAny ? "present" : "missing") source=\(source)"
                case .kimik2:
                    let resolution = ProviderTokenResolver.kimiK2Resolution(environment: processEnvironment)
                    let hasEnv = KimiK2SettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "KIMI_K2_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .copilot:
                    let resolution = ProviderTokenResolver.copilotResolution(environment: processEnvironment)
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "COPILOT_API_TOKEN=\(hasAny ? "present" : "missing") source=\(source)"
                case .perplexity:
                    let resolution = ProviderTokenResolver.perplexityResolution(environment: processEnvironment)
                    let hasEnv = PerplexitySettingsReader.sessionToken(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "PERPLEXITY_SESSION_TOKEN",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .codebuff:
                    let resolution = ProviderTokenResolver.codebuffResolution(environment: processEnvironment)
                    let hasEnv = CodebuffSettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "CODEBUFF_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .zhipu:
                    let resolution = ProviderTokenResolver.zhipuResolution(environment: processEnvironment)
                    let hasEnv = ZhipuSettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "ZHIPU_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .doubao:
                    let resolution = ProviderTokenResolver.doubaoResolution(environment: processEnvironment)
                    let hasEnv = DoubaoSettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "DOUBAO_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .ernie:
                    let resolution = ProviderTokenResolver.ernieResolution(environment: processEnvironment)
                    let hasEnv = ErnieSettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "ERNIE_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .mimo:
                    let resolution = ProviderTokenResolver.mimoResolution(environment: processEnvironment)
                    let hasEnv = MiMoSettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "MIMO_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .opencode:
                    return await Self.runWithTimeout(seconds: 15) {
                        do {
                            let session = try OpenCodeCookieImporter.importSession(browserDetection: browserDetection)
                            return "OPENCODE_COOKIE=present source=\(session.sourceLabel) cookies=\(session.cookies.count)"
                        } catch {
                            return "OPENCODE_COOKIE=missing error=\(error.localizedDescription)"
                        }
                    }
                case .abacus:
                    return await Self.runWithTimeout(seconds: 15) {
                        do {
                            let sessions = try AbacusCookieImporter.importSessions(browserDetection: browserDetection)
                            let first = sessions.first
                            return "ABACUS_COOKIE=present count=\(sessions.count) source=\(first?.sourceLabel ?? "none")"
                        } catch {
                            return "ABACUS_COOKIE=missing error=\(error.localizedDescription)"
                        }
                    }
                case .mistral:
                    return await Self.runWithTimeout(seconds: 15) {
                        do {
                            let session = try MistralCookieImporter.importSession(browserDetection: browserDetection)
                            return "MISTRAL_COOKIE=present source=\(session.sourceLabel) cookies=\(session.cookies.count)"
                        } catch {
                            return "MISTRAL_COOKIE=missing error=\(error.localizedDescription)"
                        }
                    }
                case .factory:
                    return await Self.runWithTimeout(seconds: 15) {
                        do {
                            let probe = FactoryStatusProbe(browserDetection: browserDetection)
                            let snapshot = try await probe.fetch()
                            var lines: [String] = []
                            lines.append("FACTORY_PROBE=success")
                            if let email = snapshot.accountEmail { lines.append("email=\(email)") }
                            if let plan = snapshot.planName { lines.append("plan=\(plan)") }
                            lines.append("standard=\(snapshot.standardUserTokens)/\(snapshot.standardAllowance)")
                            lines.append("premium=\(snapshot.premiumUserTokens)/\(snapshot.premiumAllowance)")
                            return lines.joined(separator: "\n")
                        } catch {
                            return "FACTORY_PROBE=failed error=\(error.localizedDescription)"
                        }
                    }
                case .gemini:
                    return await Self.runWithTimeout(seconds: 15) {
                        do {
                            let probe = GeminiStatusProbe()
                            let snapshot = try await probe.fetch()
                            var lines: [String] = []
                            lines.append("GEMINI_PROBE=success")
                            if let email = snapshot.accountEmail { lines.append("email=\(email)") }
                            if let plan = snapshot.accountPlan { lines.append("plan=\(plan)") }
                            for quota in snapshot.modelQuotas {
                                lines.append("\(quota.modelId)=\(String(format: "%.1f%%", quota.percentLeft))")
                            }
                            return lines.joined(separator: "\n")
                        } catch {
                            return "GEMINI_PROBE=failed error=\(error.localizedDescription)"
                        }
                    }
                case .antigravity:
                    return await Self.runWithTimeout(seconds: 15) {
                        do {
                            let probe = AntigravityStatusProbe()
                            let snapshot = try await probe.fetch()
                            var lines: [String] = []
                            lines.append("ANTIGRAVITY_PROBE=success")
                            if let email = snapshot.accountEmail { lines.append("email=\(email)") }
                            if let plan = snapshot.accountPlan { lines.append("plan=\(plan)") }
                            for quota in snapshot.modelQuotas {
                                let pct = quota.remainingFraction.map { String(format: "%.1f%%", $0 * 100) } ?? "n/a"
                                lines.append("\(quota.label)=\(pct)")
                            }
                            return lines.joined(separator: "\n")
                        } catch {
                            return "ANTIGRAVITY_PROBE=failed error=\(error.localizedDescription)"
                        }
                    }
                case .kiro:
                    return await Self.runWithTimeout(seconds: 15) {
                        do {
                            let probe = KiroStatusProbe()
                            let snapshot = try await probe.fetch()
                            var lines: [String] = []
                            lines.append("KIRO_PROBE=success")
                            lines.append("plan=\(snapshot.planName)")
                            lines.append("credits=\(String(format: "%.1f", snapshot.creditsUsed))/\(String(format: "%.1f", snapshot.creditsTotal)) (\(String(format: "%.1f%%", snapshot.creditsPercent)))")
                            if let bonus = snapshot.bonusCreditsUsed, let bonusTotal = snapshot.bonusCreditsTotal {
                                lines.append("bonus=\(String(format: "%.1f", bonus))/\(String(format: "%.1f", bonusTotal))")
                            }
                            return lines.joined(separator: "\n")
                        } catch {
                            return "KIRO_PROBE=failed error=\(error.localizedDescription)"
                        }
                    }
                case .jetbrains:
                    return await Self.runWithTimeout(seconds: 15) {
                        do {
                            let probe = JetBrainsStatusProbe()
                            let snapshot = try await probe.fetch()
                            var lines: [String] = []
                            lines.append("JETBRAINS_PROBE=success")
                            let q = snapshot.quotaInfo
                            if let type = q.type { lines.append("quota_type=\(type)") }
                            lines.append("used=\(String(format: "%.0f", q.used))/\(String(format: "%.0f", q.maximum))")
                            lines.append("available=\(String(format: "%.0f", q.available))")
                            if let refill = snapshot.refillInfo {
                                if let refillType = refill.type { lines.append("refill_type=\(refillType)") }
                                if let amount = refill.amount { lines.append("refill_amount=\(String(format: "%.0f", amount))") }
                            }
                            return lines.joined(separator: "\n")
                        } catch {
                            return "JETBRAINS_PROBE=failed error=\(error.localizedDescription)"
                        }
                    }
                case .opencodego:
                    return "OpenCodeGo uses local CLI authentication; no API key or cookie to probe."
                case .vertexai:
                    return "Vertex AI uses OAuth via Google Cloud; run `gcloud auth print-access-token` to verify."
                case .openai:
                    let resolution = ProviderTokenResolver.openAIAPIResolution(environment: processEnvironment)
                    let hasEnv = OpenAIAPISettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "OPENAI_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .manus:
                    return await Self.runWithTimeout(seconds: 15) {
                        "MANUS=web-based cookie; no API key to probe."
                    }
                case .moonshot:
                    let resolution = ProviderTokenResolver.moonshotResolution(environment: processEnvironment)
                    let hasEnv = MoonshotSettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "MOONSHOT_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .windsurf:
                    return await Self.runWithTimeout(seconds: 15) {
                        "WINDSURF=web-based cookie; use Settings to configure."
                    }
                case .crof:
                    let resolution = ProviderTokenResolver.crofResolution(environment: processEnvironment)
                    let hasEnv = CrofSettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "CROF_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .venice:
                    let resolution = ProviderTokenResolver.veniceResolution(environment: processEnvironment)
                    let hasEnv = VeniceSettingsReader.apiKey(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "VENICE_API_KEY",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .commandcode:
                    return await Self.runWithTimeout(seconds: 15) {
                        "COMMANDCODE=web-based cookie; use Settings to configure."
                    }
                case .stepfun:
                    let resolution = ProviderTokenResolver.stepfunResolution(environment: processEnvironment)
                    let hasEnv = StepFunSettingsReader.token(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "STEPFUN_TOKEN",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                case .bedrock:
                    let resolution = ProviderTokenResolver.bedrockResolution(environment: processEnvironment)
                    let hasEnv = BedrockSettingsReader.accessKeyID(environment: processEnvironment) != nil
                    return Self.apiKeyDebugLine(
                        label: "BEDROCK_ACCESS_KEY_ID",
                        resolution: resolution,
                        configToken: nil,
                        hasEnvToken: hasEnv)
                }
            }
            return await claudeDebugExecutionContext.apply {
                await buildText()
            }
        }.value
        self.probeLogs[provider] = text
        return text
    }

    private func makeClaudeDebugConfiguration(
        fallbackUsageDataSource: ClaudeUsageDataSource,
        fallbackWebExtrasEnabled: Bool,
        fallbackCookieSource: ProviderCookieSource,
        fallbackCookieHeader: String) async -> ClaudeDebugLogConfiguration
    {
        await MainActor.run {
            let sourceMode = self.sourceMode(for: .claude)
            let snapshot = ProviderRegistry.makeSettingsSnapshot(settings: self.settings, tokenOverride: nil)
            let environment = ProviderRegistry.makeEnvironment(
                base: self.environmentBase,
                provider: .claude,
                settings: self.settings,
                tokenOverride: nil)
            let claudeSettings = snapshot.claude ?? ProviderSettingsSnapshot.ClaudeProviderSettings(
                usageDataSource: fallbackUsageDataSource,
                webExtrasEnabled: fallbackWebExtrasEnabled,
                cookieSource: fallbackCookieSource,
                manualCookieHeader: fallbackCookieHeader)
            return ClaudeDebugLogConfiguration(
                runtime: CodexBarCore.ProviderRuntime.app,
                sourceMode: sourceMode,
                environment: environment,
                webExtrasEnabled: claudeSettings.webExtrasEnabled,
                usageDataSource: claudeSettings.usageDataSource,
                cookieSource: claudeSettings.cookieSource,
                cookieHeader: claudeSettings.manualCookieHeader ?? "",
                keepCLISessionsAlive: snapshot.debugKeepCLISessionsAlive)
        }
    }

    private struct ClaudeDebugExecutionContext {
        let interaction: ProviderInteraction
        let refreshPhase: ProviderRefreshPhase
        #if DEBUG
        let keychainServiceOverride: String?
        let credentialsURLOverride: URL?
        let testingOverrides: ClaudeOAuthCredentialsStore.TestingOverridesSnapshot
        let keychainDeniedUntilStoreOverride: ClaudeOAuthKeychainAccessGate.DeniedUntilStore?
        let keychainPromptModeOverride: ClaudeOAuthKeychainPromptMode?
        let keychainReadStrategyOverride: ClaudeOAuthKeychainReadStrategy?
        let cliPathOverride: String?
        let statusFetchOverride: ClaudeStatusProbe.FetchOverride?
        #endif

        func apply<T>(_ operation: () async -> T) async -> T {
            await ProviderInteractionContext.$current.withValue(self.interaction) {
                await ProviderRefreshContext.$current.withValue(self.refreshPhase) {
                    #if DEBUG
                    return await KeychainCacheStore.withServiceOverrideForTesting(self.keychainServiceOverride) {
                        await ClaudeOAuthCredentialsStore
                            .withCredentialsURLOverrideForTesting(self.credentialsURLOverride) {
                                await ClaudeOAuthCredentialsStore
                                    .withTestingOverridesSnapshotForTask(self.testingOverrides) {
                                        await ClaudeOAuthKeychainAccessGate
                                            .withDeniedUntilStoreOverrideForTesting(self
                                                .keychainDeniedUntilStoreOverride)
                                            {
                                                await ClaudeOAuthKeychainPromptPreference
                                                    .withTaskOverrideForTesting(self.keychainPromptModeOverride) {
                                                        await ClaudeOAuthKeychainReadStrategyPreference
                                                            .withTaskOverrideForTesting(self
                                                                .keychainReadStrategyOverride)
                                                            {
                                                                await ClaudeCLIResolver
                                                                    .withResolvedBinaryPathOverrideForTesting(self
                                                                        .cliPathOverride)
                                                                    {
                                                                        await ClaudeStatusProbe
                                                                            .withFetchOverrideForTesting(self
                                                                                .statusFetchOverride)
                                                                            {
                                                                                await operation()
                                                                            }
                                                                    }
                                                            }
                                                    }
                                            }
                                    }
                            }
                    }
                    #else
                    return await operation()
                    #endif
                }
            }
        }
    }

    private func currentClaudeDebugExecutionContext() -> ClaudeDebugExecutionContext {
        #if DEBUG
        ClaudeDebugExecutionContext(
            interaction: ProviderInteractionContext.current,
            refreshPhase: ProviderRefreshContext.current,
            keychainServiceOverride: KeychainCacheStore.currentServiceOverrideForTesting,
            credentialsURLOverride: ClaudeOAuthCredentialsStore.currentCredentialsURLOverrideForTesting,
            testingOverrides: ClaudeOAuthCredentialsStore.currentTestingOverridesSnapshotForTask,
            keychainDeniedUntilStoreOverride: ClaudeOAuthKeychainAccessGate.currentDeniedUntilStoreOverrideForTesting,
            keychainPromptModeOverride: ClaudeOAuthKeychainPromptPreference.currentTaskOverrideForTesting,
            keychainReadStrategyOverride: ClaudeOAuthKeychainReadStrategyPreference.currentTaskOverrideForTesting,
            cliPathOverride: ClaudeCLIResolver.currentResolvedBinaryPathOverrideForTesting,
            statusFetchOverride: ClaudeStatusProbe.currentFetchOverrideForTesting)
        #else
        ClaudeDebugExecutionContext(
            interaction: ProviderInteractionContext.current,
            refreshPhase: ProviderRefreshContext.current)
        #endif
    }

    private nonisolated static func apiKeyDebugLine(
        label: String,
        resolution: ProviderTokenResolution?,
        configToken: String?,
        hasEnvToken: Bool,
        hasTokenAccount: Bool = false) -> String
    {
        let hasAny = resolution != nil
        let hasConfigToken = !(configToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let source: String = if resolution == nil {
            "none"
        } else if hasTokenAccount, hasEnvToken {
            "settings-token-account (overrides env)"
        } else if hasTokenAccount {
            "settings-token-account"
        } else if hasConfigToken, hasEnvToken {
            "settings-config (overrides env)"
        } else if hasConfigToken {
            "settings-config"
        } else {
            resolution?.source.rawValue ?? "environment"
        }
        return "\(label)=\(hasAny ? "present" : "missing") source=\(source)"
    }

    private static func debugCursorLog(
        browserDetection: BrowserDetection,
        cursorCookieSource: ProviderCookieSource,
        cursorCookieHeader: String) async -> String
    {
        await runWithTimeout(seconds: 15) {
            var lines: [String] = []

            do {
                let probe = CursorStatusProbe(browserDetection: browserDetection)
                let snapshot: CursorStatusSnapshot = if cursorCookieSource == .manual,
                                                        let normalizedHeader = CookieHeaderNormalizer
                                                            .normalize(cursorCookieHeader)
                {
                    try await probe.fetchWithManualCookies(normalizedHeader)
                } else {
                    try await probe.fetch { msg in lines.append("[cursor-cookie] \(msg)") }
                }

                lines.append("")
                lines.append("Cursor Status Summary:")
                lines.append("membershipType=\(snapshot.membershipType ?? "nil")")
                lines.append("accountEmail=\(snapshot.accountEmail ?? "nil")")
                lines.append("planPercentUsed=\(snapshot.planPercentUsed)%")
                lines.append("planUsedUSD=$\(snapshot.planUsedUSD)")
                lines.append("planLimitUSD=$\(snapshot.planLimitUSD)")
                lines.append("onDemandUsedUSD=$\(snapshot.onDemandUsedUSD)")
                lines.append("onDemandLimitUSD=\(snapshot.onDemandLimitUSD.map { "$\($0)" } ?? "nil")")
                if let teamUsed = snapshot.teamOnDemandUsedUSD {
                    lines.append("teamOnDemandUsedUSD=$\(teamUsed)")
                }
                if let teamLimit = snapshot.teamOnDemandLimitUSD {
                    lines.append("teamOnDemandLimitUSD=$\(teamLimit)")
                }
                lines.append("billingCycleEnd=\(snapshot.billingCycleEnd?.description ?? "nil")")

                if let rawJSON = snapshot.rawJSON {
                    lines.append("")
                    lines.append("Raw API Response:")
                    lines.append(rawJSON)
                }

                return lines.joined(separator: "\n")
            } catch {
                lines.append("")
                lines.append("Cursor probe failed: \(error.localizedDescription)")
                return lines.joined(separator: "\n")
            }
        }
    }

    private static func debugAugmentLog() async -> String {
        await runWithTimeout(seconds: 15) {
            let probe = AugmentStatusProbe()
            return await probe.debugRawProbe()
        }
    }

    private static func debugAmpLog(
        browserDetection: BrowserDetection,
        ampCookieSource: ProviderCookieSource,
        ampCookieHeader: String) async -> String
    {
        await runWithTimeout(seconds: 15) {
            let fetcher = AmpUsageFetcher(browserDetection: browserDetection)
            let manualHeader = ampCookieSource == .manual
                ? CookieHeaderNormalizer.normalize(ampCookieHeader)
                : nil
            return await fetcher.debugRawProbe(cookieHeaderOverride: manualHeader)
        }
    }

    private static func debugOllamaLog(
        browserDetection: BrowserDetection,
        ollamaCookieSource: ProviderCookieSource,
        ollamaCookieHeader: String) async -> String
    {
        await runWithTimeout(seconds: 15) {
            let fetcher = OllamaUsageFetcher(browserDetection: browserDetection)
            let manualHeader = ollamaCookieSource == .manual
                ? CookieHeaderNormalizer.normalize(ollamaCookieHeader)
                : nil
            return await fetcher.debugRawProbe(
                cookieHeaderOverride: manualHeader,
                manualCookieMode: ollamaCookieSource == .manual)
        }
    }

    private func detectVersions() {
        let implementations = ProviderCatalog.all
        let browserDetection = self.browserDetection
        Task { @MainActor [weak self] in
            let resolved = await Task.detached { () -> [UsageProvider: String] in
                var resolved: [UsageProvider: String] = [:]
                await withTaskGroup(of: (UsageProvider, String?).self) { group in
                    for implementation in implementations {
                        let context = ProviderVersionContext(
                            provider: implementation.id,
                            browserDetection: browserDetection)
                        group.addTask {
                            await (implementation.id, implementation.detectVersion(context: context))
                        }
                    }
                    for await (provider, version) in group {
                        guard let version, !version.isEmpty else { continue }
                        resolved[provider] = version
                    }
                }
                return resolved
            }.value
            self?.versions = resolved
        }
    }

    @MainActor
    private func schedulePathDebugInfoRefresh() {
        self.pathDebugRefreshTask?.cancel()
        self.pathDebugRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            await self?.refreshPathDebugInfo()
        }
    }

    private func runBackgroundSnapshot(
        _ snapshot: @escaping @Sendable () async -> PathDebugSnapshot) async
    {
        let result = await snapshot()
        await MainActor.run {
            self.pathDebugInfo = result
        }
    }

    private func refreshPathDebugInfo() async {
        await self.runBackgroundSnapshot {
            await PathBuilder.debugSnapshotAsync(purposes: [.rpc, .tty, .nodeTooling])
        }
    }

    func clearCostUsageCache() async -> String? {
        let errorMessage: String? = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let cacheDirs = [
                Self.costUsageCacheDirectory(fileManager: fm),
            ]

            for cacheDir in cacheDirs {
                do {
                    try fm.removeItem(at: cacheDir)
                } catch let error as NSError {
                    if error.domain == NSCocoaErrorDomain, error.code == NSFileNoSuchFileError { continue }
                    return error.localizedDescription
                }
            }
            return nil
        }.value

        guard errorMessage == nil else { return errorMessage }

        self.tokenSnapshots.removeAll()
        self.tokenErrors.removeAll()
        self.lastTokenFetchAt.removeAll()
        self.tokenFailureGates[.codex]?.reset()
        self.tokenFailureGates[.claude]?.reset()
        return nil
    }

    private func refreshTokenUsage(_ provider: UsageProvider, force: Bool) async {
        guard provider == .codex || provider == .claude || provider == .vertexai else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        guard self.settings.costUsageEnabled else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        guard self.isEnabled(provider) else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            return
        }

        guard !self.tokenRefreshInFlight.contains(provider) else { return }

        let now = Date()
        if !force,
           let last = self.lastTokenFetchAt[provider],
           now.timeIntervalSince(last) < self.tokenFetchTTL
        {
            return
        }
        self.lastTokenFetchAt[provider] = now
        self.tokenRefreshInFlight.insert(provider)
        defer { self.tokenRefreshInFlight.remove(provider) }

        let startedAt = Date()
        let providerText = provider.rawValue
        self.tokenCostLogger
            .debug("cost usage start provider=\(providerText) force=\(force)")

        do {
            let fetcher = self.costUsageFetcher
            let timeoutSeconds = self.tokenFetchTimeout
            // CostUsageFetcher scans local Codex session logs from this machine. That data is
            // intentionally presented as provider-level local telemetry rather than managed-account
            // remote state, so managed Codex account selection does not retarget this fetch.
            // If the UI later needs account-scoped token history, it should label and source that
            // separately instead of silently changing the meaning of this section.
            let snapshot = try await withThrowingTaskGroup(of: CostUsageTokenSnapshot.self) { group in
                group.addTask(priority: .utility) {
                    try await fetcher.loadTokenSnapshot(
                        provider: provider,
                        now: now,
                        forceRefresh: force,
                        allowVertexClaudeFallback: !self.isEnabled(.claude))
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw CostUsageError.timedOut(seconds: Int(timeoutSeconds))
                }
                defer { group.cancelAll() }
                guard let snapshot = try await group.next() else { throw CancellationError() }
                return snapshot
            }

            guard !snapshot.daily.isEmpty else {
                self.tokenSnapshots.removeValue(forKey: provider)
                self.tokenErrors[provider] = Self.tokenCostNoDataMessage(for: provider)
                self.tokenFailureGates[provider]?.recordSuccess()
                return
            }
            let duration = Date().timeIntervalSince(startedAt)
            let sessionCost = snapshot.sessionCostUSD.map(UsageFormatter.usdString) ?? "—"
            let monthCost = snapshot.last30DaysCostUSD.map(UsageFormatter.usdString) ?? "—"
            let durationText = String(format: "%.2f", duration)
            let message =
                "cost usage success provider=\(providerText) " +
                "duration=\(durationText)s " +
                "today=\(sessionCost) " +
                "30d=\(monthCost)"
            self.tokenCostLogger.info(message)
            self.tokenSnapshots[provider] = snapshot
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.recordSuccess()
            self.persistWidgetSnapshot(reason: "token-usage")
        } catch {
            if error is CancellationError { return }
            let duration = Date().timeIntervalSince(startedAt)
            let msg = error.localizedDescription
            let durationText = String(format: "%.2f", duration)
            let message = "cost usage failed provider=\(providerText) duration=\(durationText)s error=\(msg)"
            self.tokenCostLogger.error(message)
            let hadPriorData = self.tokenSnapshots[provider] != nil
            let shouldSurface = self.tokenFailureGates[provider]?
                .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
            if shouldSurface {
                self.tokenErrors[provider] = error.localizedDescription
                self.tokenSnapshots.removeValue(forKey: provider)
            } else {
                self.tokenErrors[provider] = nil
            }
        }
    }
}
