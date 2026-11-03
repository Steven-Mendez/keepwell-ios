import Domain
import Foundation
import Observation
import TransactionsDomain

@MainActor
@Observable
public final class AddTransactionViewModel {
    /// Transfers aren't offered until accounts exist (see `DomainError.unsupportedTransactionKind`).
    public let availableKinds: [TransactionKind] = [.expense, .income]
    public let availableCurrencies: [String]

    public var amount: Decimal?
    public var currency: String
    public var kind: TransactionKind = .expense {
        didSet {
            // Keep the category valid for the new kind; the use case would reject a mismatch.
            if category.kind != kind, let first = availableCategories.first {
                category = first
            }
        }
    }

    public var category: TransactionCategory
    public var date: Date
    public var note = ""
    public var isPlanned = false
    public private(set) var isSaving = false
    public var error: DomainError?

    public var availableCategories: [TransactionCategory] {
        TransactionCategory.defaults(for: kind)
    }

    public var canSave: Bool {
        guard let amount else { return false }
        return amount > 0 && !isSaving
    }

    @ObservationIgnored private let addTransaction: any AddTransactionUseCase

    public init(addTransaction: any AddTransactionUseCase, currencies: [String], date: Date = .now) {
        self.addTransaction = addTransaction
        availableCurrencies = currencies
        currency = currencies.first ?? "USD"
        category = TransactionCategory.defaultExpense.first
            ?? TransactionCategory(id: "other-expense", name: "Otros", kind: .expense)
        self.date = date
    }

    /// Returns `true` once stored; on failure `error` is set and the form keeps its input.
    public func save() async -> Bool {
        guard let amount, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let draft = Transaction(
            amount: amount,
            currency: currency,
            kind: kind,
            category: category,
            date: date,
            note: note,
            status: isPlanned ? .planned : .confirmed,
        )
        do throws(DomainError) {
            try await addTransaction.execute(draft)
            return true
        } catch {
            self.error = error
            return false
        }
    }
}
