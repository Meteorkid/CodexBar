import Foundation
import Testing
@testable import CodexBarCore

struct ManusUsageFetcherTests {
    @Test
    func `credits response decodes correctly`() throws {
        let json = """
        {
            "totalCredits": 1000,
            "freeCredits": 500,
            "periodicCredits": 300,
            "addonCredits": 100,
            "refreshCredits": 50,
            "maxRefreshCredits": 200,
            "proMonthlyCredits": 0,
            "eventCredits": 50,
            "nextRefreshTime": "2026-07-01T00:00:00Z",
            "refreshInterval": "monthly"
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ManusCreditsResponse.self, from: data)
        #expect(response.totalCredits == 1000)
        #expect(response.freeCredits == 500)
        #expect(response.periodicCredits == 300)
    }
}
