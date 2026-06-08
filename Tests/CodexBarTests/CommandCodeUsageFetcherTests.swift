import Foundation
import Testing
@testable import CodexBarCore

struct CommandCodeUsageFetcherTests {
    @Test
    func `parses credits payload`() throws {
        let json = """
        {
          "credits": {
            "monthlyCredits": 12.5,
            "purchasedCredits": 3,
            "premiumMonthlyCredits": 1,
            "opensourceMonthlyCredits": 0.5
          }
        }
        """
        let payload = try CommandCodeUsageFetcher.parseCredits(data: Data(json.utf8))
        #expect(payload.monthlyCredits == 12.5)
        #expect(payload.purchasedCredits == 3)
        #expect(payload.premiumMonthlyCredits == 1)
        #expect(payload.opensourceMonthlyCredits == 0.5)
    }

    @Test
    func `parses active subscription payload`() throws {
        let json = """
        {
          "success": true,
          "data": {
            "planId": "pro_monthly",
            "status": "active",
            "currentPeriodEnd": "2026-05-01T00:00:00.000Z"
          }
        }
        """
        let payload = try CommandCodeUsageFetcher.parseSubscription(data: Data(json.utf8))
        #expect(payload?.planID == "pro_monthly")
        #expect(payload?.status == "active")
        #expect(payload?.currentPeriodEnd != nil)
    }

    @Test
    func `subscription free tier returns nil`() throws {
        let json = """
        {
          "success": false
        }
        """
        let payload = try CommandCodeUsageFetcher.parseSubscription(data: Data(json.utf8))
        #expect(payload == nil)
    }
}
