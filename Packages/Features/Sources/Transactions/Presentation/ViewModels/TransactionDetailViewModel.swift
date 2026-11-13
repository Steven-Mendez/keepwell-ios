import Core
import Domain
import Foundation
import Observation
import SharedPresentation
import TransactionsDomain

/// One movement in full, as the web's detail panel shows it: the amount, what it was, where it
/// went, its status, rate, note, tags and the recurring rule behind it, with its actions.
@MainActor
@Observable
public final class TransactionDetailViewModel {
    public enum State: Equatable {
        case loading
        case loaded(TransactionList)
        /// Deleted here or elsewhere since the screen opened.
        case missing
        case failed
    }

    /// "Label · value" on the detail cards.
    public struct Row: Hashable, Sendable {
        public let label: String
        public let value: String
    }

    public let transactionID: UUID
    public private(set) var state = State.loading
    public private(set) var actionError: String?
    /// Set once the movement is deleted, so the screen can close.
    public private(set) var isDeleted = false
    /// A short confirmation over the screen ("Saved", "Rule saved"), set by whoever changed it.
    public var notice: String?

    private let getList: any GetTransactionListUseCase
    private let confirmPlanned: any ConfirmPlannedTransactionUseCase
    private let deleteTransaction: any DeleteTransactionUseCase
    /// Offers "Undo" after a delete or a confirm; `nil` in previews.
    private let undo: MovementUndo?
    let formatter = CurrencyFormatter()

    public init(
        transactionID: UUID,
        getList: any GetTransactionListUseCase,
        confirmPlanned: any ConfirmPlannedTransactionUseCase,
        deleteTransaction: any DeleteTransactionUseCase,
        undo: MovementUndo? = nil,
    ) {
        self.undo = undo
        self.transactionID = transactionID
        self.getList = getList
        self.confirmPlanned = confirmPlanned
        self.deleteTransaction = deleteTransaction
    }

    public func load() async {
        do {
            let list = try await getList.execute()
            state = list.transactions.contains { $0.id == transactionID } ? .loaded(list) : .missing
        } catch {
            state = .failed
        }
    }

    public var list: TransactionList? {
        if case let .loaded(list) = state {
            list
        } else {
            nil
        }
    }

    public var transaction: Transaction? {
        list?.transactions.first { $0.id == transactionID }
    }

    // MARK: Actions

    public func confirm() async {
        let planned = transaction
        do {
            try await confirmPlanned.execute(id: transactionID)
            actionError = nil
            if let planned {
                undo?.offerConfirmed(planned)
            }
            await load()
        } catch {
            actionError = String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
        }
    }

    public func delete() async {
        let deleted = transaction
        do {
            try await deleteTransaction.execute(id: transactionID)
            actionError = nil
            if let deleted {
                undo?.offerDeleted(deleted)
            }
            isDeleted = true
        } catch {
            actionError = String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
        }
    }

    public var canConfirm: Bool {
        transaction.map { !$0.isConfirmed } == true
    }

    /// Splitting is for expenses: others then owe part of what the person paid.
    public var canSplit: Bool {
        transaction?.kind == .expense
    }

    // MARK: Display

    var display: TransactionDisplay? {
        list.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }

    /// The live recurring rule that recorded it; `nil` once that rule is deleted.
    public var recurringRule: RecurringRule? {
        guard let list, let transaction else { return nil }
        return list.recurringRule(of: transaction)
    }

    /// "Every month" next to "Repeats".
    var recurringText: String? {
        recurringRule.map(RecurringDisplay.frequency(of:))
    }

    var statusText: String {
        transaction?.isConfirmed == false
            ? String(localized: "Draft", bundle: #bundle)
            : String(localized: "Confirmed", bundle: #bundle)
    }

    var kindText: String {
        switch transaction?.kind {
        case .income: String(localized: "kind.income", defaultValue: "Income", bundle: #bundle)
        case .transfer: String(localized: "kind.transfer", defaultValue: "Transfer", bundle: #bundle)
        case .expense, nil: String(localized: "kind.expense", defaultValue: "Expense", bundle: #bundle)
        }
    }

    /// "Nov 3, 2026 at 9:22 AM", in the person's language.
    var dateText: String {
        transaction?.date.formatted(date: .abbreviated, time: .shortened) ?? ""
    }

    /// Where it went: the category and method of an expense or income, or both ends of a transfer.
    var routeRows: [Row] {
        guard let transaction, let display else { return [] }
        switch transaction.kind {
        case .transfer:
            return [
                Row(label: String(localized: "From", bundle: #bundle), value: display.methodName(of: transaction)),
                Row(label: String(localized: "To", bundle: #bundle), value: display.accountName(transaction.destinationAccountID)),
            ]
        case .expense, .income:
            let method = transaction.kind == .expense
                ? String(localized: "Paid with", bundle: #bundle)
                : String(localized: "Into", bundle: #bundle)
            return [
                Row(label: String(localized: "Category", bundle: #bundle), value: display.categoryName(of: transaction) ?? "—"),
                Row(label: method, value: display.methodName(of: transaction)),
            ]
        }
    }

    /// The rate it was recorded with, and the bank's own when it reported a real debit. Only for
    /// a movement that involved the second currency.
    var rateRows: [Row] {
        guard let transaction, transaction.exchangeRate.hasSecondCurrency else { return [] }
        let rate = transaction.exchangeRate
        var rows = [Row(label: String(localized: "Rate used", bundle: #bundle), value: formatter.rate(rate))]
        if let bankRate = transaction.bankRate {
            rows.append(Row(label: String(localized: "Bank rate", bundle: #bundle), value: "\(formatter.number(bankRate)) \(rate.second)"))
        }
        return rows
    }

    /// A short code to find the movement again, the same one its receipt shows.
    var reference: String {
        "KW-" + transactionID.uuidString.prefix(8).uppercased()
    }
}
