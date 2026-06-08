import Foundation
import Testing
@testable import CodexBarCore

struct MoonshotUsageFetcherTests {
    @Test
    func `snapshot converts to usage snapshot`() {
        let summary = MoonshotUsageSummary(
            availableBalance: 100,
            voucherBalance: 50,
            cashBalance: 50,
            updatedAt: Date())
        let snapshot = MoonshotUsageSnapshot(summary: summary)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.provider == .moonshot)
    }

    @Test
    func `summary has correct fields`() {
        let summary = MoonshotUsageSummary(
            availableBalance: 100,
            voucherBalance: 50,
            cashBalance: 50,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(summary.availableBalance == 100)
        #expect(summary.voucherBalance == 50)
        #expect(summary.cashBalance == 50)
    }
}
