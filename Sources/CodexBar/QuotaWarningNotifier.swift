import CodexBarCore
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class QuotaWarningNotifier {
    private let logger = CodexBarLog.logger(LogCategories.quotaWarningNotifications)

    private var lastSessionRemaining: [UsageProvider: Double] = [:]
    private var lastWeeklyRemaining: [UsageProvider: Double] = [:]

    func evaluate(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        settings: SettingsStore)
    {
        guard settings.quotaWarningNotificationsEnabled else { return }

        let sessionThresholds = settings.quotaWarningThresholds(.session)
        let weeklyThresholds = settings.quotaWarningThresholds(.weekly)
        let sound: UNNotificationSound? = settings.quotaWarningSoundEnabled ? .default : nil

        if settings.quotaWarningWindowEnabled(.session), !sessionThresholds.isEmpty {
            self.evaluateWindow(
                provider: provider,
                window: snapshot.primary,
                thresholds: sessionThresholds,
                lastRemaining: &self.lastSessionRemaining,
                windowLabel: "session",
                sound: sound)
        }

        if settings.quotaWarningWindowEnabled(.weekly), !weeklyThresholds.isEmpty {
            self.evaluateWindow(
                provider: provider,
                window: snapshot.secondary,
                thresholds: weeklyThresholds,
                lastRemaining: &self.lastWeeklyRemaining,
                windowLabel: "weekly",
                sound: sound)
        }
    }

    private func evaluateWindow(
        provider: UsageProvider,
        window: RateWindow?,
        thresholds: [Int],
        lastRemaining: inout [UsageProvider: Double],
        windowLabel: String,
        sound: UNNotificationSound?)
    {
        guard let window else {
            lastRemaining.removeValue(forKey: provider)
            return
        }

        let current = window.remainingPercent
        let previous = lastRemaining[provider]
        lastRemaining[provider] = current

        guard let previous else { return }

        var fired: [Int] = []
        for threshold in thresholds {
            if previous > Double(threshold), current <= Double(threshold) {
                fired.append(threshold)
            }
        }

        guard !fired.isEmpty else { return }

        let displayName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        let thresholdText = fired.map { "\($0)%" }.joined(separator: ", ")
        let percentText = String(format: "%.0f%%", current)

        self.logger.info(
            "threshold crossed",
            metadata: [
                "provider": provider.rawValue,
                "window": windowLabel,
                "thresholds": thresholdText,
                "current": percentText])

        let title = "\(displayName) \(windowLabel) quota"
        let body = "\(percentText) remaining — crossed \(thresholdText)"

        AppNotifications.shared.post(
            idPrefix: "quota-warning-\(provider.rawValue)-\(windowLabel)-\(thresholdText)",
            title: title,
            body: body,
            soundEnabled: sound != nil)
    }
}
