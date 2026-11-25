import Core
import DebtsDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// A split expense's people: each share and whether it was paid, "Mark as paid" (optionally
/// deposited into an account) and back, and the public link to send them.
@MainActor
@Observable
public final class SplitDetailViewModel: Identifiable {
    public let id = UUID()
    public private(set) var transaction: Transaction
    public private(set) var debts: [PersonalDebt] = []
    /// Where a repayment can be deposited: the open bank and cash accounts. Empty until `load()`.
    public private(set) var depositAccounts: [Account] = []
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    private var currencies: CurrencySettings?
    private let split: any SplitTransactionUseCase
    private let useCases: DebtsUseCases
    /// The web app the link opens on; `nil` without a Keepwell account that syncs, since the server
    /// then has nothing to show.
    private let web: URL?
    private let now: () -> Date
    let formatter = CurrencyFormatter()

    public init(
        transaction: Transaction,
        split: any SplitTransactionUseCase,
        useCases: DebtsUseCases,
        web: URL?,
        now: @escaping () -> Date = { .now },
    ) {
        self.transaction = transaction
        self.split = split
        self.useCases = useCases
        self.web = web
        self.now = now
    }

    public func load() async {
        debts = await (try? split.shares(of: transaction)) ?? []
        guard let context = try? await useCases.paymentContext.execute() else { return }
        currencies = context.currencies
        depositAccounts = context.accounts.open.filter { $0.kind != .credit }
    }

    public var subtitle: String {
        "\(transaction.description) · \(formatter.string(from: transaction.amount, currencyCode: transaction.currency))"
    }

    public func amount(_ debt: PersonalDebt) -> String {
        formatter.string(debt.amount)
    }

    /// "Paid", "Paid C$100.00 of C$247.37" or "Pending".
    public func status(_ debt: PersonalDebt) -> String {
        if debt.isSettled {
            return String(localized: "Paid", bundle: #bundle)
        }
        if debt.repaid > 0 {
            let repaid = formatter.string(from: debt.repaid, currencyCode: debt.amount.currency)
            return String(localized: "Paid \(repaid) of \(amount(debt))", bundle: #bundle)
        }
        return String(localized: "Pending", bundle: #bundle)
    }

    /// Accounts the rest of this share can be deposited into; empty when it can't be.
    public func depositAccounts(for debt: PersonalDebt) -> [Account] {
        guard let currencies, debt.canDepositRepayment(currencies: currencies) else { return [] }
        return depositAccounts
    }

    public func accountName(_ account: Account) -> String {
        CardDisplay.name(of: account)
    }

    /// "Mark as paid": what is left is recorded as repaid, into `accountID` when one is given.
    public func markPaid(_ debt: PersonalDebt, depositInto accountID: UUID?) async {
        let remaining = debt.remaining
        let today = now()
        let deposit = accountID.map { RepaymentDeposit(accountID: $0) }
        await run { [useCases] in try await useCases.updateDebt.repay(id: debt.id, amount: remaining, on: today, deposit: deposit) }
    }

    /// The repayment that settled the debt the moment it was paid; undoing it opens the debt again.
    private func settlingRepayment(_ debt: PersonalDebt) -> DebtRepayment? {
        guard let last = debt.repayments.last, last.date == debt.settledAt else { return nil }
        return last
    }

    /// Whether "Mark as unpaid" also deletes an income it deposited, which deserves a confirmation.
    public func unpayingDeletesIncome(_ debt: PersonalDebt) -> Bool {
        settlingRepayment(debt)?.transactionID != nil
    }

    public func markUnpaid(_ debt: PersonalDebt) async {
        if let repayment = settlingRepayment(debt) {
            await run { [useCases] in try await useCases.updateDebt.deleteRepayment(debtID: debt.id, repaymentID: repayment.id) }
        } else {
            await run { [useCases] in try await useCases.updateDebt.reopen(id: debt.id) }
        }
    }

    /// A live link exists only with an account that syncs; without one, a summary is shared instead.
    public var canShareLink: Bool {
        web != nil
    }

    public var shareURL: URL? {
        guard let web, let token = transaction.shareToken else { return nil }
        return SplitSharing.url(token: token, web: web)
    }

    public func share() async {
        await runOnExpense { [split, transaction] in try await split.share(transactionID: transaction.id) }
    }

    public func stopSharing() async {
        await runOnExpense { [split, transaction] in try await split.stopSharing(transactionID: transaction.id) }
    }

    /// What is sent without a link: the expense, then each share and who already paid.
    public var summary: String {
        let lines = debts.map { debt in
            debt.isSettled
                ? String(localized: "\(debt.person): \(amount(debt)), paid", bundle: #bundle)
                : "\(debt.person): \(amount(debt))"
        }
        return ([subtitle] + lines).joined(separator: "\n")
    }

    private func run(_ work: @Sendable () async throws -> PersonalDebt) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await work()
            debts = debts.map { $0.id == updated.id ? updated : $0 }
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "We couldn't save the debt. Try again.", bundle: #bundle)
        }
    }

    private func runOnExpense(_ work: @Sendable () async throws -> Transaction) async {
        isSaving = true
        defer { isSaving = false }
        do {
            transaction = try await work()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "We couldn't save the debt. Try again.", bundle: #bundle)
        }
    }
}
