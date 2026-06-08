import Foundation
import Testing
@testable import CodexBarCore

struct VeniceUsageFetcherTests {
    @Test
    func `balance response decodes correctly`() throws {
        let json = """
        {
            "canConsume": true,
            "consumptionCurrency": "USD",
            "balances": {
                "diem": 100.0,
                "credits": 500.0
            },
            "diemEpochAllocation": 200.0
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(VeniceBalanceResponse.self, from: data)
        #expect(response.canConsume == true)
        #expect(response.consumptionCurrency == "USD")
        #expect(response.balances.diem == 100.0)
        #expect(response.balances.credits == 500.0)
        #expect(response.diemEpochAllocation == 200.0)
    }

    @Test
    func `error cases`() {
        let missing = VeniceUsageError.missingCredentials
        #expect(missing.errorDescription?.contains("Missing") == true)

        let network = VeniceUsageError.networkError("timeout")
        #expect(network.errorDescription?.contains("timeout") == true)
    }
}
