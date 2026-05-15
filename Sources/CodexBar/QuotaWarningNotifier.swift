import CodexBarCore
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class QuotaWarningNotifier {
    private let logger = CodexBarLog.logger(LogCategories.quotaWarning)

    private var lastSessionRemaining: [UsageProvider: Double] = [:]
    private var lastWeeklyRemaining: [UsageProvider: Double] = [:]

    func evaluate(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        settings: SettingsStore)
    {
        guard settings.quotaWarningNotificationsEnabled else { return }

        let thresholds = QuotaWarningThresholds.active(settings.quotaWarningThresholdsRaw)
        guard !thresholds.isEmpty else { return }

        let sound: UNNotificationSound? = settings.quotaWarningSoundEnabled ? .default : nil

        if settings.quotaWarningSessionEnabled {
            self.evaluateWindow(
                provider: provider,
                window: snapshot.primary,
                thresholds: thresholds,
                lastRemaining: &self.lastSessionRemaining,
                windowLabel: "session",
                sound: sound)
        }

        if settings.quotaWarningWeeklyEnabled {
            self.evaluateWindow(
                provider: provider,
                window: snapshot.secondary,
                thresholds: thresholds,
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
            sound: sound)
    }
}
