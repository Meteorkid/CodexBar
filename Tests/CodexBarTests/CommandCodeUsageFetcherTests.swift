import Foundation
import Testing
@testable import CodexBarCore

struct CommandCodeUsageFetcherTests {
    @Test
    func `snapshot converts to usage snapshot`() {
        let snapshot = CommandCodeUsageSnapshot(
            credits: 100,
            plan: .pro,
            periodEnd: Date(),
            updatedAt: Date())
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.provider == .commandCode)
    }

    @Test
    func `error cases`() {
        let missing = CommandCodeUsageError.missingCredentials
        #expect(missing.errorDescription?.contains("Missing") == true)

        let network = CommandCodeUsageError.networkError("timeout")
        #expect(network.errorDescription?.contains("timeout") == true)
    }
}
