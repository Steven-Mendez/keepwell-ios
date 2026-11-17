import CreateTransactionDomain
import DebtsDomain
import DebtsPresentation
import Domain

// MARK: - Debts

extension AppContainer {
    func makeDebtsViewModel() -> DebtsViewModel {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: movements,
        )
        let recorder = InstallmentMovementRecorder(prepare: DefaultPrepareTransactionUseCase(context: context))
        return DebtsViewModel(useCases: DebtsUseCases(
            getDebts: DefaultGetDebtsUseCase(loans: store, debts: store, settings: store),
            saveLoan: DefaultSaveLoanUseCase(loans: store, settings: store),
            payInstallment: DefaultPayLoanInstallmentUseCase(loans: store, recorder: recorder),
            paymentContext: context,
            saveDebt: DefaultSavePersonalDebtUseCase(debts: store, settings: store),
            updateDebt: DefaultUpdatePersonalDebtUseCase(
                debts: store, categories: store, settings: store, recorder: recorder,
            ),
            delete: DefaultDeleteDebtUseCase(loans: store, debts: store),
        ))
    }

    func makeSplitBillViewModel(_ transaction: Transaction) -> SplitBillViewModel {
        SplitBillViewModel(
            transaction: transaction,
            split: DefaultSplitTransactionUseCase(transactions: movements, debts: store),
        )
    }
}
