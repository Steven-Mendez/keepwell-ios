import CreateTransactionDomain
import DebtsDomain
import Domain
import Foundation

/// Pays an installment through the movement-saving use case, so it is validated, dated and rated
/// exactly like a movement the person types and shows up confirmed in their list.
public struct SaveTransactionInstallmentRecorder: InstallmentExpenseRecorder {
    private let save: any SaveTransactionUseCase

    public init(save: any SaveTransactionUseCase) {
        self.save = save
    }

    public func record(_ expense: InstallmentExpense) async throws(DomainError) -> UUID {
        let saved = try await save.execute(TransactionDraft(
            kind: .expense,
            amount: expense.amount.amount,
            currency: expense.amount.currency,
            categoryID: expense.categoryID,
            source: expense.source.paymentSource,
            description: expense.description,
            date: expense.date,
        ))
        return saved.transaction.id
    }
}

extension InstallmentSource {
    init(_ source: PaymentSource) {
        switch source {
        case let .card(id): self = .card(id)
        case let .account(id): self = .account(id)
        }
    }

    var paymentSource: PaymentSource {
        switch self {
        case let .card(id): .card(id)
        case let .account(id): .account(id)
        }
    }
}
