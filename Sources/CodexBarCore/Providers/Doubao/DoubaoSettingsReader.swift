import Foundation

public struct DoubaoSettingsReader: Sendable {
    public static let apiKeyEnvironmentKey = "DOUBAO_API_KEY"
    public static let apiKeyEnvironmentKeys = [Self.apiKeyEnvironmentKey, "VOLCENGINE_API_KEY"]
    public static let baseURLKey = "DOUBAO_BASE_URL"
    private static let defaultBaseURL = URL(string: "https://ark.cn-beijing.volces.com/api/v3")!

    public static func baseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
    {
        if let raw = environment[baseURLKey], !raw.isEmpty {
            let cleaned = self.cleaned(raw)
            if !cleaned.isEmpty, let url = URL(string: cleaned) { return url }
        }
        return self.defaultBaseURL
    }

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        for key in self.apiKeyEnvironmentKeys {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else {
                continue
            }
            let cleaned = Self.cleaned(raw)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    private static func cleaned(_ raw: String) -> String {
        var value = raw
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value.removeFirst()
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
