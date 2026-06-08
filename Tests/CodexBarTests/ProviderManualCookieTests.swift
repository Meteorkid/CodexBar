import Testing
@testable import CodexBarCore

struct ProviderManualCookieTests {
    @Test
    func `auto mode returns nil override`() throws {
        let override = try ProviderManualCookie.cookieHeaderOverride(
            cookieSource: .auto,
            rawHeader: "session=abc")
        #expect(override == nil)
    }

    @Test
    func `manual mode returns normalized header`() throws {
        let override = try ProviderManualCookie.cookieHeaderOverride(
            cookieSource: .manual,
            rawHeader: "  session=abc; path=/  ")
        #expect(override?.contains("session=abc") == true)
    }

    @Test
    func `manual mode rejects empty header`() {
        #expect(throws: ProviderManualCookie.ResolutionError.self) {
            try ProviderManualCookie.cookieHeaderOverride(
                cookieSource: .manual,
                rawHeader: "   ")
        }
    }
}
