import CreateTransactionDomain
import CreateTransactionPresentation
import Domain
import Foundation
import TransactionsDomain
import TransactionsPresentation

// MARK: - A saved movement: its detail, editing it and its receipt

extension AppContainer {
    func makeTransactionDetailViewModel(id: UUID) -> TransactionDetailViewModel {
        TransactionDetailViewModel(
            transactionID: id,
            getList: DefaultGetTransactionListUseCase(
                transactions: movements, accounts: store, cards: store, categories: store, settings: store, recurringRules: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: movements),
            deleteTransaction: DeferredDeleteTransactionUseCase(deletions: movements),
            undo: movementUndo,
        )
    }

    /// The create flow opened on a saved movement's review; saving replaces it and may offer a rule.
    func makeEditTransactionViewModel(id: UUID) -> CreateTransactionViewModel {
        let stored = makeGetStoredTransaction()
        return CreateTransactionViewModel(
            stored: .edit(id),
            getStored: stored,
            update: DefaultUpdateTransactionUseCase(stored: stored, transactions: movements, settings: store),
            manageRules: DefaultManageCategorizationRulesUseCase(rules: store, categories: store, transactions: movements),
            saveCategory: DefaultSaveCategoryUseCase(categories: store),
        )
    }

    /// The receipt the create flow ends on, rebuilt for a saved movement.
    func makeTransactionReceiptViewModel(id: UUID) -> CreateTransactionViewModel {
        CreateTransactionViewModel(
            stored: .receipt(id),
            getStored: makeGetStoredTransaction(),
            receiptSaver: PhotoLibraryReceiptSaver(),
        )
    }

    private func makeGetStoredTransaction() -> DefaultGetTransactionContextUseCase {
        DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: movements, rules: store,
        )
    }
}
