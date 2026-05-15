import Foundation

public enum QuotaWarningWindow: String, Codable, Sendable, CaseIterable {
    case session
    case weekly

    public var displayName: String {
        switch self {
        case .session: "session"
        case .weekly: "weekly"
        }
    }
}

public struct QuotaWarningWindowConfig: Codable, Sendable, Equatable {
    public var thresholds: [Int]
    public var enabled: Bool?

    public init(thresholds: [Int] = [], enabled: Bool? = nil) {
        self.thresholds = thresholds
        self.enabled = enabled
    }
}

public struct QuotaWarningConfig: Codable, Sendable, Equatable {
    public var session: QuotaWarningWindowConfig
    public var weekly: QuotaWarningWindowConfig

    public init(session: QuotaWarningWindowConfig = .init(),
                weekly: QuotaWarningWindowConfig = .init()) {
        self.session = session
        self.weekly = weekly
    }
}

public enum QuotaWarningThresholds {
    public static let defaults = [50, 20]
    public static let allowedRange = 0...99

    public static func sanitized(_ thresholds: [Int]) -> [Int] {
        let clamped = thresholds.map { max(allowedRange.lowerBound, min(allowedRange.upperBound, $0)) }
        return Array(Set(clamped)).sorted(by: >)
    }

    public static func active(_ thresholds: [Int]) -> [Int] {
        sanitized(thresholds).filter { $0 > 0 && $0 < 100 }
    }
}
