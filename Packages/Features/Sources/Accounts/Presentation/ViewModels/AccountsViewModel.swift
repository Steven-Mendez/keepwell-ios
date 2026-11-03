import AccountsDomain
import Core
import Domain
import Foundation
import Observation

@MainActor
@Observable
public final class AccountsViewModel {
    public enum State: Equatable {
        case loading
        case loaded(AccountsOverview)
        case failed
    }

    public private(set) var state = State.loading
    /// Shown inside the cash sheets when saving fails.
    public private(set) var actionError: String?

    private let getOverview: any GetAccountsOverviewUseCase
    private let reconcileCash: any ReconcileCashUseCase
    private let withdrawCash: any WithdrawCashUseCase

    public init(
        getOverview: any GetAccountsOverviewUseCase,
        reconcileCash: any ReconcileCashUseCase,
        withdrawCash: any WithdrawCashUseCase,
    ) {
        self.getOverview = getOverview
        self.reconcileCash = reconcileCash
        self.withdrawCash = withdrawCash
    }

    public var overview: AccountsOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public func load() async {
        do {
            state = try await .loaded(getOverview.execute())
        } catch {
            state = .failed
        }
    }

    /// Returns whether the sheet can close.
    public func reconcile(_ cash: AccountsOverview.Cash, countedText: String) async -> Bool {
        guard let counted = AmountInput.decimal(from: countedText) else {
            actionError = String(localized: "Enter how much cash you have.", bundle: #bundle)
            return false
        }
        let description = String(localized: "Cash adjustment", bundle: #bundle)
        return await perform { () async throws(DomainError) in
            try await reconcileCash.execute(cash: cash, counted: counted, description: description)
        }
    }

    /// `debitedText` is optional: empty means the bank used the app's rate.
    public func withdraw(into cash: AccountsOverview.Cash, from sourceID: UUID, amountText: String, debitedText: String) async -> Bool {
        guard let amount = AmountInput.decimal(from: amountText), amount > 0 else {
            actionError = String(localized: "Enter the amount you withdrew.", bundle: #bundle)
            return false
        }
        let trimmed = debitedText.trimmingCharacters(in: .whitespaces)
        let debited = trimmed.isEmpty ? nil : AmountInput.decimal(from: trimmed)
        if !trimmed.isEmpty, debited == nil {
            actionError = String(localized: "Check the amount the bank charged you.", bundle: #bundle)
            return false
        }
        let withdrawal = CashWithdrawal(
            sourceAccountID: sourceID,
            cashAccountID: cash.account.id,
            amount: Money(amount, cash.balance.currency),
            debitedPrincipal: debited,
            description: String(localized: "ATM withdrawal", bundle: #bundle),
        )
        return await perform { () async throws(DomainError) in
            try await withdrawCash.execute(withdrawal)
        }
    }

    public func clearActionError() {
        actionError = nil
    }

    private func perform(_ action: () async throws(DomainError) -> some Any) async -> Bool {
        do {
            _ = try await action()
            actionError = nil
            await load()
            return true
        } catch {
            actionError = String(localized: "We couldn't save. Try again.", bundle: #bundle)
            return false
        }
    }
}
