import Foundation
import Testing
@testable import CodexBarCore

struct KimiK2UsageFetcherTests {
    @Test
    func `snapshot converts to usage snapshot`() {
        let summary = KimiK2UsageSummary(
            consumed: 1000,
            remaining: 5000,
            averageTokens: 200,
            updatedAt: Date())
        let snapshot = KimiK2UsageSnapshot(summary: summary)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.provider == .kimiK2)
    }

    @Test
    func `summary has correct fields`() {
        let summary = KimiK2UsageSummary(
            consumed: 1000,
            remaining: 5000,
            averageTokens: 200,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(summary.consumed == 1000)
        #expect(summary.remaining == 5000)
        #expect(summary.averageTokens == 200)
    }
}
