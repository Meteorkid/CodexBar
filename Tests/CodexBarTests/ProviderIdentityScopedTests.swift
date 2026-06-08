import CodexBarCore
import Foundation
import Testing

struct ProviderIdentityScopedTests {
    @Test
    func `scoped clears fields when provider id is nil`() {
        let identity = ProviderIdentitySnapshot(
            providerID: nil,
            accountEmail: "other@example.com",
            accountOrganization: "Org",
            loginMethod: "pro")
        let scoped = identity.scoped(to: .claude)
        #expect(scoped.providerID == .claude)
        #expect(scoped.accountEmail == nil)
        #expect(scoped.accountOrganization == nil)
        #expect(scoped.loginMethod == nil)
    }

    @Test
    func `scoped clears fields when provider id mismatches`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "codex@example.com",
            accountOrganization: nil,
            loginMethod: "plus")
        let scoped = identity.scoped(to: .claude)
        #expect(scoped.providerID == .claude)
        #expect(scoped.accountEmail == nil)
        #expect(scoped.loginMethod == nil)
    }

    @Test
    func `scoped preserves fields when provider id matches`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: "claude@example.com",
            accountOrganization: "Acme",
            loginMethod: "max")
        let scoped = identity.scoped(to: .claude)
        #expect(scoped.providerID == identity.providerID)
        #expect(scoped.accountEmail == identity.accountEmail)
        #expect(scoped.loginMethod == identity.loginMethod)
    }

    @Test
    func `usage snapshot scoped drops mismatched identity fields`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "codex@example.com",
                accountOrganization: nil,
                loginMethod: nil))
        let scoped = snapshot.scoped(to: .claude)
        #expect(scoped.accountEmail(for: .claude) == nil)
        #expect(scoped.identity(for: .codex) == nil)
    }
}
