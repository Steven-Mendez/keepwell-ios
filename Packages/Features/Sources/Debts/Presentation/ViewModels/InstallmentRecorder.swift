import CreateTransactionDomain
import DebtsDomain
import Domain
import Foundation

/// Builds an installment's expense through the movement-saving rules, so it is validated, dated and
/// rated exactly like a movement the person types and shows up confirmed in their list.
public struct InstallmentMovementRecorder: InstallmentExpenseRecorder {
    private let prepare: any PrepareTransactionUseCase

    public init(prepare: any PrepareTransactionUseCase) {
        self.prepare = prepare
    }

    public func prepare(_ expense: InstallmentExpense) async throws(DomainError) -> Transaction {
        try await prepare.execute(TransactionDraft(
            kind: .expense,
            amount: expense.amount.amount,
            currency: expense.amount.currency,
            categoryID: expense.categoryID,
            source: expense.source.paymentSource,
            description: expense.description,
            date: expense.date,
        ))
    }
}

/// Builds a deposited repayment's income through the same movement-saving rules.
extension InstallmentMovementRecorder: RepaymentIncomeRecorder {
    public func prepare(_ income: RepaymentIncome) async throws(DomainError) -> Transaction {
        try await prepare.execute(TransactionDraft(
            kind: .income,
            amount: income.amount.amount,
            currency: income.amount.currency,
            categoryID: income.categoryID,
            source: .account(income.accountID),
            description: income.description,
            date: income.date,
        ))
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
