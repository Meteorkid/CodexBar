import Foundation

public struct ErnieSettingsReader: Sendable {
    public static let apiKeyEnvironmentKey = "QIANFAN_API_KEY"
    public static let apiKeyEnvironmentKeys = [Self.apiKeyEnvironmentKey, "ERNIE_API_KEY", "BAIDU_API_KEY"]
    public static let baseURLKey = "ERNIE_BASE_URL"
    private static let defaultBaseURL = URL(string: "https://qianfan.baidubce.com/v2")!

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
