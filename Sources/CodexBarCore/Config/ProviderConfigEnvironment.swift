import Foundation

public enum ProviderConfigEnvironment {
    public static func applyAPIKeyOverride(
        base: [String: String],
        provider: UsageProvider,
        config: ProviderConfig?) -> [String: String]
    {
        guard let apiKey = config?.sanitizedAPIKey, !apiKey.isEmpty else { return base }
        var env = base
        switch provider {
        case .zai:
            env[ZaiSettingsReader.apiTokenKey] = apiKey
        case .copilot:
            env["COPILOT_API_TOKEN"] = apiKey
        case .minimax:
            env[MiniMaxAPISettingsReader.apiTokenKey] = apiKey
        case .alibaba:
            env[AlibabaCodingPlanSettingsReader.apiTokenKey] = apiKey
        case .kilo:
            env[KiloSettingsReader.apiTokenKey] = apiKey
        case .kimik2:
            if let key = KimiK2SettingsReader.apiKeyEnvironmentKeys.first {
                env[key] = apiKey
            }
        case .synthetic:
            env[SyntheticSettingsReader.apiKeyKey] = apiKey
        case .warp:
            if let key = WarpSettingsReader.apiKeyEnvironmentKeys.first {
                env[key] = apiKey
            }
        case .openrouter:
            env[OpenRouterSettingsReader.envKey] = apiKey
        case .codebuff:
            // Preserve a token already present in the process environment so that
            // runtime/CI overrides win over a key saved in Settings (matches the
            // precedence used by `ProviderTokenResolver.codebuffResolution`).
            if CodebuffSettingsReader.apiKey(environment: base) == nil {
                env[CodebuffSettingsReader.apiTokenKey] = apiKey
            }
        case .mimo:
            if let key = MiMoSettingsReader.apiKeyEnvironmentKeys.first {
                env[key] = apiKey
            }
        case .deepseek:
            if let key = DeepSeekSettingsReader.apiKeyEnvironmentKeys.first {
                env[key] = apiKey
            }
        case .doubao:
            if let key = DoubaoSettingsReader.apiKeyEnvironmentKeys.first {
                env[key] = apiKey
            }
        case .ernie:
            if let key = ErnieSettingsReader.apiKeyEnvironmentKeys.first {
                env[key] = apiKey
            }
        case .zhipu:
            if let key = ZhipuSettingsReader.apiKeyEnvironmentKeys.first {
                env[key] = apiKey
            }
        case .kimi:
            env["KIMI_AUTH_TOKEN"] = apiKey
        case .perplexity:
            env["PERPLEXITY_SESSION_TOKEN"] = apiKey
        default:
            break
        }
        return env
    }

    public static func applyBaseURLOverride(
        base: [String: String],
        provider: UsageProvider,
        config: ProviderConfig?) -> [String: String]
    {
        guard let baseURL = config?.sanitizedBaseURL, !baseURL.isEmpty else { return base }
        var env = base
        let key: String? = switch provider {
        case .deepseek: DeepSeekSettingsReader.baseURLKey
        case .doubao: DoubaoSettingsReader.baseURLKey
        case .ernie: ErnieSettingsReader.baseURLKey
        case .zhipu: ZhipuSettingsReader.baseURLKey
        case .kimi: KimiSettingsReader.baseURLKey
        case .kimik2: KimiK2SettingsReader.baseURLKey
        case .mimo: MiMoSettingsReader.baseURLKey
        case .openrouter: "OPENROUTER_API_URL"
        default: nil
        }
        if let key {
            env[key] = baseURL
        }
        return env
    }
}
