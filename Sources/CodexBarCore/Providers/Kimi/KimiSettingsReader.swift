import Foundation

public enum KimiSettingsReader {
    public static let baseURLKey = "KIMI_BASE_URL"
    private static let defaultBaseURL = URL(string: "https://www.kimi.com")!

    public static func baseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
    {
        if let raw = environment[baseURLKey], !raw.isEmpty,
           let cleaned = self.cleaned(raw),
           let url = URL(string: cleaned)
        {
            return url
        }
        return self.defaultBaseURL
    }

    public static func authToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let raw = environment["KIMI_AUTH_TOKEN"] ?? environment["kimi_auth_token"]
        return self.cleaned(raw)
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value = String(value.dropFirst().dropLast())
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
