import Testing
@testable import CodexBarCore

struct WindsurfSessionParsingTests {
    @Test
    func `parses json manual session input`() throws {
        let json = """
        {
          "devin_session_token": "session",
          "devin_auth1_token": "auth1",
          "devin_account_id": "acct",
          "devin_primary_org_id": "org"
        }
        """
        let auth = try WindsurfWebFetcher.parseManualSessionInput(json)
        #expect(auth.sessionToken == "session")
        #expect(auth.auth1Token == "auth1")
        #expect(auth.accountID == "acct")
        #expect(auth.primaryOrgID == "org")
    }

    @Test
    func `rejects empty manual session input`() {
        #expect(throws: WindsurfWebFetcherError.self) {
            try WindsurfWebFetcher.parseManualSessionInput("   ")
        }
    }
}
