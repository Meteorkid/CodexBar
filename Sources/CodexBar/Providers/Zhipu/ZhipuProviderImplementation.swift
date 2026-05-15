import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct ZhipuProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .zhipu

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.zhipuAPIToken
        _ = settings.zhipuCookieSource
        _ = settings.zhipuManualCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .zhipu(context.settings.zhipuSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if ZhipuSettingsReader.apiKey(environment: context.environment) != nil {
            return true
        }
        return !context.settings.zhipuAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.zhipuCookieSource.rawValue },
            set: { raw in
                context.settings.zhipuCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let options = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let subtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.zhipuCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatic imports browser cookies.",
                manual: "Paste the full Cookie header value.",
                off: "Zhipu cookies are disabled.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "zhipu-cookie-source",
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
                id: "zhipu-base-url",
                title: "API base URL",
                subtitle: "Override the default API endpoint.",
                kind: .plain,
                placeholder: "https://open.bigmodel.cn/api/paas/v4",
                binding: context.stringBinding(\.zhipuBaseURL),
                actions: [],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "zhipu-api-key",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. "
                    + "Get your key from open.bigmodel.cn/usercenter.",
                kind: .secure,
                placeholder: "sk-...",
                binding: context.stringBinding(\.zhipuAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "zhipu-open-api",
                        title: "Open API Keys",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://open.bigmodel.cn/usercenter/apikeys") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "zhipu-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: \u{2026}\n\nPaste the full Cookie header from open.bigmodel.cn",
                binding: context.stringBinding(\.zhipuManualCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "zhipu-get-cookies",
                        title: "Get Cookies",
                        style: .bordered,
                        isVisible: nil,
                        perform: {
                            CookieBookmarklet.openInstructions()
                        }),
                    ProviderSettingsActionDescriptor(
                        id: "zhipu-open-console",
                        title: "Open Console",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://open.bigmodel.cn/usercenter") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.zhipuCookieSource == .manual },
                onActivate: nil),
        ]
    }
}
