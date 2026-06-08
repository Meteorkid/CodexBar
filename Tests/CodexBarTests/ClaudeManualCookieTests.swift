import Testing
@testable import CodexBarCore

struct ClaudeManualCookieTests {
    @Test
    func `manual mode ignores browser when header is invalid`() {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let hasSession = ClaudeManualCookie.hasWebSession(
            cookieSource: .manual,
            rawHeader: "   ",
            browserDetection: browserDetection)
        #expect(hasSession == false)
    }

    @Test
    func `manual mode accepts normalized session header`() {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let hasSession = ClaudeManualCookie.hasWebSession(
            cookieSource: .manual,
            rawHeader: "sessionKey=sk-ant-test-session; path=/",
            browserDetection: browserDetection)
        #expect(hasSession == true)
    }

    @Test
    func `manual resolved header throws when empty`() {
        #expect(throws: ProviderManualCookie.ResolutionError.self) {
            try ClaudeManualCookie.resolvedWebCookieHeader(
                cookieSource: .manual,
                rawHeader: "  ")
        }
    }

    @Test
    func `off mode never resolves web header`() throws {
        let header = try ClaudeManualCookie.resolvedWebCookieHeader(
            cookieSource: .off,
            rawHeader: "sessionKey=sk-ant-test-session")
        #expect(header == nil)
    }
}
