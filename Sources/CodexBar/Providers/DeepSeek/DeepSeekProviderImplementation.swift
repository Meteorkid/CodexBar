import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct DeepSeekProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .deepseek

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "api" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.deepSeekAPIToken
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if DeepSeekSettingsReader.apiKey(environment: context.environment) != nil {
            return true
        }
        return !context.settings.deepSeekAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "deepseek-base-url",
                title: "API base URL",
                subtitle: "Override the default API endpoint.",
                kind: .plain,
                placeholder: "https://api.deepseek.com",
                binding: context.stringBinding(\.deepSeekBaseURL),
                actions: [],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "deepseek-api-key",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. "
                    + "Get your key from platform.deepseek.com.",
                kind: .secure,
                placeholder: "sk-...",
                binding: context.stringBinding(\.deepSeekAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "deepseek-open-platform",
                        title: "Open Platform",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://platform.deepseek.com/api_keys") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
