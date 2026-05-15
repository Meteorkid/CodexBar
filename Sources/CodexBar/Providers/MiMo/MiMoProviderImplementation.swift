import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct MiMoProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .mimo

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.mimoAPIToken
        _ = settings.mimoCookieSource
        _ = settings.mimoManualCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .mimo(context.settings.mimoSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if MiMoSettingsReader.apiKey(environment: context.environment) != nil {
            return true
        }
        return !context.settings.mimoAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.mimoCookieSource.rawValue },
            set: { raw in
                context.settings.mimoCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let options = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let subtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.mimoCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatic imports browser cookies.",
                manual: "Paste the full Cookie header value.",
                off: "MiMo cookies are disabled.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "mimo-cookie-source",
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
                id: "mimo-base-url",
                title: "API base URL",
                subtitle: "Override the default API endpoint.",
                kind: .plain,
                placeholder: "https://token-plan-sgp.xiaomimimo.com/anthropic",
                binding: context.stringBinding(\.mimoBaseURL),
                actions: [],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "mimo-api-key",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. "
                    + "Get your key from platform.xiaomimimo.com.",
                kind: .secure,
                placeholder: "tp-...",
                binding: context.stringBinding(\.mimoAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "mimo-open-platform",
                        title: "Open Platform",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://platform.xiaomimimo.com") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "mimo-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: \u{2026}\n\nPaste the full Cookie header from platform.xiaomimimo.com",
                binding: context.stringBinding(\.mimoManualCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "mimo-get-cookies",
                        title: "Get Cookies",
                        style: .bordered,
                        isVisible: nil,
                        perform: {
                            CookieBookmarklet.openInstructions()
                        }),
                    ProviderSettingsActionDescriptor(
                        id: "mimo-open-console",
                        title: "Open Console",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://platform.xiaomimimo.com/console/balance") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.mimoCookieSource == .manual },
                onActivate: nil),
        ]
    }
}
