import Foundation

public enum ProviderManualCookie {
    public enum ResolutionError: LocalizedError, Sendable {
        case missingManualHeader

        public var errorDescription: String? {
            switch self {
            case .missingManualHeader:
                "Manual cookie header is empty or invalid."
            }
        }
    }

    /// Returns a cookie header override for fetchers, or `nil` when browser import should run.
    /// Throws when manual mode is selected but the header cannot be normalized.
    public static func cookieHeaderOverride(
        cookieSource: ProviderCookieSource,
        rawHeader: String?) throws -> String?
    {
        guard cookieSource == .manual else { return nil }
        guard let header = CookieHeaderNormalizer.normalize(rawHeader) else {
            throw ResolutionError.missingManualHeader
        }
        return header
    }
}
