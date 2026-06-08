import Foundation

enum ClaudeManualCookie {
    static func hasWebSession(
        cookieSource: ProviderCookieSource,
        rawHeader: String?,
        browserDetection: BrowserDetection) -> Bool
    {
        switch cookieSource {
        case .manual:
            guard let header = try? ProviderManualCookie.cookieHeaderOverride(
                cookieSource: .manual,
                rawHeader: rawHeader),
                ClaudeWebAPIFetcher.hasSessionKey(cookieHeader: header)
            else {
                return false
            }
            return true
        case .auto:
            if let header = CookieHeaderNormalizer.normalize(rawHeader),
               ClaudeWebAPIFetcher.hasSessionKey(cookieHeader: header)
            {
                return true
            }
            return ClaudeWebAPIFetcher.hasSessionKey(browserDetection: browserDetection)
        case .off:
            return false
        }
    }

    static func resolvedWebCookieHeader(
        cookieSource: ProviderCookieSource,
        rawHeader: String?) throws -> String?
    {
        switch cookieSource {
        case .manual:
            try ProviderManualCookie.cookieHeaderOverride(
                cookieSource: .manual,
                rawHeader: rawHeader)
        case .auto:
            CookieHeaderNormalizer.normalize(rawHeader)
        case .off:
            nil
        }
    }
}
