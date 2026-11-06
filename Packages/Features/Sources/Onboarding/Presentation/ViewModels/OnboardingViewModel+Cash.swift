import Foundation
import OnboardingDomain

/// Cash accounts: one per chosen currency, named by currency once there are two.
extension OnboardingViewModel {
    /// The currencies a cash account can hold: its own plus any without cash yet.
    public func cashCurrencyOptions(for draft: OnboardingAccountDraft) -> [String] {
        let free = freeCashCurrencies(excluding: draft.id)
        return currencies.filter { $0 == draft.currency || free.contains($0) }
    }

    var currencies: [String] {
        [principal, second].compactMap(\.self)
    }

    func freeCashCurrencies(excluding id: UUID?) -> [String] {
        let taken = Set(accounts.filter { $0.kind == .cash && $0.id != id }.map(\.currency))
        return currencies.filter { !taken.contains($0) }
    }

    /// With cash in two currencies, "Cash" alone can't tell them apart in the app's lists.
    var accountsToSave: [OnboardingAccountDraft] {
        let cashCount = accounts.count { $0.kind == .cash }
        guard cashCount > 1 else { return accounts }
        return accounts.map { account in
            guard account.kind == .cash else { return account }
            var named = account
            let currency = account.currency
            named.name = String(localized: "Cash \(currency)", bundle: #bundle)
            return named
        }
    }
}
