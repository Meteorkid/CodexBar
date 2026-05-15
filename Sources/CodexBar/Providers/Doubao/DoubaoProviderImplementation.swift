import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct DoubaoProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .doubao

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.doubaoAPIToken
        _ = settings.doubaoCookieSource
        _ = settings.doubaoManualCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .doubao(context.settings.doubaoSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if DoubaoSettingsReader.apiKey(environment: context.environment) != nil {
            return true
        }
        return !context.settings.doubaoAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.doubaoCookieSource.rawValue },
            set: { raw in
                context.settings.doubaoCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let options = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let subtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.doubaoCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatic imports browser cookies.",
                manual: "Paste the full Cookie header value.",
                off: "Doubao cookies are disabled.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "doubao-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies.",
                dynamicSubtitle: subtitle,
                binding: cookieBinding,
                options: options,
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "doubao-base-url",
                title: "API base URL",
                subtitle: "Override the default API endpoint.",
                kind: .plain,
                placeholder: "https://ark.cn-beijing.volces.com/api/v3",
                binding: context.stringBinding(\.doubaoBaseURL),
                actions: [],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "doubao-api-key",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. "
                    + "Get your key from console.volcengine.com/ark.",
                kind: .secure,
                placeholder: "sk-...",
                binding: context.stringBinding(\.doubaoAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "doubao-open-api",
                        title: "Open API Keys",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://console.volcengine.com/ark/api-key") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "doubao-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: \u{2026}\n\nPaste the full Cookie header from console.volcengine.com",
                binding: context.stringBinding(\.doubaoManualCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "doubao-get-cookies",
                        title: "Get Cookies",
                        style: .bordered,
                        isVisible: nil,
                        perform: {
                            CookieBookmarklet.openInstructions()
                        }),
                    ProviderSettingsActionDescriptor(
                        id: "doubao-open-console",
                        title: "Open Console",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://console.volcengine.com/ark") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.doubaoCookieSource == .manual },
                onActivate: nil),
        ]
    }
}
