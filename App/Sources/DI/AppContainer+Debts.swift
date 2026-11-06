import CreateTransactionDomain
import DebtsDomain
import DebtsPresentation
import Domain

// MARK: - Debts

extension AppContainer {
    func makeDebtsViewModel() -> DebtsViewModel {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store,
        )
        return DebtsViewModel(useCases: DebtsUseCases(
            getDebts: DefaultGetDebtsUseCase(loans: store, debts: store, settings: store),
            saveLoan: DefaultSaveLoanUseCase(loans: store, settings: store),
            payInstallment: DefaultPayLoanInstallmentUseCase(
                loans: store,
                recorder: SaveTransactionInstallmentRecorder(save: DefaultSaveTransactionUseCase(context: context, transactions: store)),
            ),
            paymentContext: context,
            saveDebt: DefaultSavePersonalDebtUseCase(debts: store, settings: store),
            updateDebt: DefaultUpdatePersonalDebtUseCase(debts: store),
            delete: DefaultDeleteDebtUseCase(loans: store, debts: store),
        ))
    }

    func makeSplitBillViewModel(_ transaction: Transaction) -> SplitBillViewModel {
        SplitBillViewModel(
            transaction: transaction,
            split: DefaultSplitTransactionUseCase(transactions: store, debts: store),
        )
    }
}
