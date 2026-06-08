import Foundation
import Testing
@testable import CodexBarCore

struct CrofUsageFetcherTests {
    @Test
    func `response decodes correctly`() throws {
        let json = """
        {
            "credits": 100,
            "requests_plan": 1000,
            "usable_requests": 500
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(CrofUsageResponse.self, from: data)
        #expect(response.credits == 100)
        #expect(response.requestsPlan == 1000)
        #expect(response.usableRequests == 500)
    }

    @Test
    func `error cases`() {
        let missing = CrofUsageError.missingCredentials
        #expect(missing.errorDescription?.contains("Missing") == true)

        let network = CrofUsageError.networkError("timeout")
        #expect(network.errorDescription?.contains("timeout") == true)

        let api = CrofUsageError.apiError(429)
        #expect(api.errorDescription?.contains("429") == true)
    }
}
