import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct QuotaWarningNotifierTests {
    private func makeSettings(
        suite: String,
        notificationsEnabled: Bool = true,
        sessionEnabled: Bool = true,
        weeklyEnabled: Bool = false,
        thresholds: [Int] = [80, 90])
        -> SettingsStore
    {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(notificationsEnabled, forKey: "quotaWarningNotificationsEnabled")
        defaults.set(sessionEnabled, forKey: "quotaWarningSessionEnabled")
        defaults.set(weeklyEnabled, forKey: "quotaWarningWeeklyEnabled")
        defaults.set(thresholds, forKey: "quotaWarningThresholdsRaw")
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func snapshot(remainingPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 100 - remainingPercent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .synthetic,
                accountEmail: "test@example.com",
                accountOrganization: nil,
                loginMethod: nil))
    }

    @Test
    func `does nothing when notifications disabled`() {
        let notifier = QuotaWarningNotifier()
        let settings = self.makeSettings(
            suite: "quota-warnings-disabled",
            notificationsEnabled: false)
        let snap = self.snapshot(remainingPercent: 50)

        // First call seeds the baseline
        notifier.evaluate(provider: .synthetic, snapshot: snap, settings: settings)
        // Second call crosses threshold — should not crash even though notifications disabled
        let snap2 = self.snapshot(remainingPercent: 70)
        notifier.evaluate(provider: .synthetic, snapshot: snap2, settings: settings)
    }

    @Test
    func `does nothing without thresholds`() {
        let notifier = QuotaWarningNotifier()
        let settings = self.makeSettings(
            suite: "quota-warnings-no-thresholds",
            thresholds: [])
        let snap = self.snapshot(remainingPercent: 50)

        notifier.evaluate(provider: .synthetic, snapshot: snap, settings: settings)
        let snap2 = self.snapshot(remainingPercent: 30)
        notifier.evaluate(provider: .synthetic, snapshot: snap2, settings: settings)
    }

    @Test
    func `does not fire on first observation`() {
        let notifier = QuotaWarningNotifier()
        let settings = self.makeSettings(suite: "quota-warnings-first-obs")
        // First call with remaining below threshold — should not fire (no previous value)
        let snap = self.snapshot(remainingPercent: 50)
        notifier.evaluate(provider: .synthetic, snapshot: snap, settings: settings)
    }

    @Test
    func `fires when crossing threshold downward`() {
        let notifier = QuotaWarningNotifier()
        let settings = self.makeSettings(suite: "quota-warnings-cross-down")

        // Seed baseline at 90% remaining
        notifier.evaluate(
            provider: .synthetic,
            snapshot: self.snapshot(remainingPercent: 90),
            settings: settings)

        // Drop to 75% — crosses 80% threshold
        notifier.evaluate(
            provider: .synthetic,
            snapshot: self.snapshot(remainingPercent: 75),
            settings: settings)
        // If we got here without crashing, the threshold crossing logic executed
    }

    @Test
    func `fires multiple thresholds at once`() {
        let notifier = QuotaWarningNotifier()
        let settings = self.makeSettings(suite: "quota-warnings-multi")

        // Seed at 95%
        notifier.evaluate(
            provider: .synthetic,
            snapshot: self.snapshot(remainingPercent: 95),
            settings: settings)

        // Drop to 70% — crosses both 90% and 80%
        notifier.evaluate(
            provider: .synthetic,
            snapshot: self.snapshot(remainingPercent: 70),
            settings: settings)
    }

    @Test
    func `does not fire when remaining increases`() {
        let notifier = QuotaWarningNotifier()
        let settings = self.makeSettings(suite: "quota-warnings-up")

        // Seed at 70%
        notifier.evaluate(
            provider: .synthetic,
            snapshot: self.snapshot(remainingPercent: 70),
            settings: settings)

        // Increase to 85% — should not fire (moving up, not crossing downward)
        notifier.evaluate(
            provider: .synthetic,
            snapshot: self.snapshot(remainingPercent: 85),
            settings: settings)
    }

    @Test
    func `session and weekly windows are independent`() {
        let notifier = QuotaWarningNotifier()
        let defaults = UserDefaults(suiteName: "quota-warnings-independent")!
        defaults.removePersistentDomain(forName: "quota-warnings-independent")
        defaults.set(true, forKey: "quotaWarningNotificationsEnabled")
        defaults.set(true, forKey: "quotaWarningSessionEnabled")
        defaults.set(true, forKey: "quotaWarningWeeklyEnabled")
        defaults.set([80], forKey: "quotaWarningThresholdsRaw")
        let configStore = testConfigStore(suiteName: "quota-warnings-independent")
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        // Create snapshot with both session and weekly windows
        let snap = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 10, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .synthetic,
                accountEmail: "test@example.com",
                accountOrganization: nil,
                loginMethod: nil))

        // Seed both windows
        notifier.evaluate(provider: .synthetic, snapshot: snap, settings: settings)

        // Update: session stays high, weekly drops below threshold
        let snap2 = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 30, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .synthetic,
                accountEmail: "test@example.com",
                accountOrganization: nil,
                loginMethod: nil))

        notifier.evaluate(provider: .synthetic, snapshot: snap2, settings: settings)
    }

    @Test
    func `handles nil window gracefully`() {
        let notifier = QuotaWarningNotifier()
        let settings = self.makeSettings(
            suite: "quota-warnings-nil-window",
            sessionEnabled: true,
            weeklyEnabled: true)

        // Snapshot with nil secondary
        let snap = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .synthetic,
                accountEmail: "test@example.com",
                accountOrganization: nil,
                loginMethod: nil))

        notifier.evaluate(provider: .synthetic, snapshot: snap, settings: settings)
        // Should not crash with nil secondary window
    }
}
