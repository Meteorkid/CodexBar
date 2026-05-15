import CodexBarCore
import Foundation

enum ProviderImplementationRegistry {
    private final class Store: @unchecked Sendable {
        var ordered: [any ProviderImplementation] = []
        var byID: [UsageProvider: any ProviderImplementation] = [:]
    }

    private static let lock = NSLock()
    private static let store = Store()

    /// 宏 `@ProviderImplementationRegistration` 已在模块加载时自动注册。
    /// 但为确保非宏路径（如测试 target）也能工作，此处会补齐遗漏。
    private static func createImplementation(for provider: UsageProvider) -> any ProviderImplementation {
        switch provider {
        case .codex: return CodexProviderImplementation()
        case .openai: return OpenAIAPIProviderImplementation()
        case .claude: return ClaudeProviderImplementation()
        case .cursor: return CursorProviderImplementation()
        case .opencode: return OpenCodeProviderImplementation()
        case .opencodego: return OpenCodeGoProviderImplementation()
        case .alibaba: return AlibabaCodingPlanProviderImplementation()
        case .factory: return FactoryProviderImplementation()
        case .gemini: return GeminiProviderImplementation()
        case .antigravity: return AntigravityProviderImplementation()
        case .copilot: return CopilotProviderImplementation()
        case .zai: return ZaiProviderImplementation()
        case .minimax: return MiniMaxProviderImplementation()
        case .manus: return ManusProviderImplementation()
        case .kimi: return KimiProviderImplementation()
        case .kilo: return KiloProviderImplementation()
        case .kiro: return KiroProviderImplementation()
        case .vertexai: return VertexAIProviderImplementation()
        case .augment: return AugmentProviderImplementation()
        case .jetbrains: return JetBrainsProviderImplementation()
        case .kimik2: return KimiK2ProviderImplementation()
        case .moonshot: return MoonshotProviderImplementation()
        case .amp: return AmpProviderImplementation()
        case .ollama: return OllamaProviderImplementation()
        case .synthetic: return SyntheticProviderImplementation()
        case .openrouter: return OpenRouterProviderImplementation()
        case .windsurf: return WindsurfProviderImplementation()
        case .warp: return WarpProviderImplementation()
        case .perplexity: return PerplexityProviderImplementation()
        case .abacus: return AbacusProviderImplementation()
        case .mistral: return MistralProviderImplementation()
        case .deepseek: return DeepSeekProviderImplementation()
        case .codebuff: return CodebuffProviderImplementation()
        case .crof: return CrofProviderImplementation()
        case .venice: return VeniceProviderImplementation()
        case .commandcode: return CommandCodeProviderImplementation()
        case .stepfun: return StepFunProviderImplementation()
        case .bedrock: return BedrockProviderImplementation()
        case .zhipu: return ZhipuProviderImplementation()
        case .doubao: return DoubaoProviderImplementation()
        case .ernie: return ErnieProviderImplementation()
        case .mimo: return MiMoProviderImplementation()
        }
    }

    /// 宏 `@ProviderImplementationRegistration` 已在模块加载时自动注册。
    /// 但为确保非宏路径（如测试 target）也能工作，此处会补齐遗漏。
    private static let bootstrap: Void = {
        for provider in UsageProvider.allCases {
            if store.byID[provider] == nil {
                let imp = createImplementation(for: provider)
                _ = ProviderImplementationRegistry.register(imp)
            }
        }
    }()

    private static func ensureBootstrapped() {
        _ = self.bootstrap
    }

    @discardableResult
    static func register(_ implementation: any ProviderImplementation) -> any ProviderImplementation {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.store.byID[implementation.id] == nil {
            self.store.ordered.append(implementation)
        }
        self.store.byID[implementation.id] = implementation
        return implementation
    }

    static var all: [any ProviderImplementation] {
        self.ensureBootstrapped()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.store.ordered
    }

    static func implementation(for id: UsageProvider) -> (any ProviderImplementation)? {
        self.ensureBootstrapped()
        if let found = self.store.byID[id] { return found }
        return self.all.first(where: { $0.id == id })
    }
}
