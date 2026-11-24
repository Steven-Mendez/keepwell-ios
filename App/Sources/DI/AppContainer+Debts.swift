import CreateTransactionDomain
import DebtsDomain
import DebtsPresentation
import Domain

// MARK: - Debts

extension AppContainer {
    func makeDebtsViewModel() -> DebtsViewModel {
        DebtsViewModel(useCases: makeDebtsUseCases())
    }

    private func makeDebtsUseCases() -> DebtsUseCases {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: movements,
        )
        let recorder = InstallmentMovementRecorder(prepare: DefaultPrepareTransactionUseCase(context: context))
        return DebtsUseCases(
            getDebts: DefaultGetDebtsUseCase(loans: store, debts: store, settings: store),
            saveLoan: DefaultSaveLoanUseCase(loans: store, settings: store),
            payInstallment: DefaultPayLoanInstallmentUseCase(loans: store, recorder: recorder),
            paymentContext: context,
            saveDebt: DefaultSavePersonalDebtUseCase(debts: store, settings: store),
            updateDebt: DefaultUpdatePersonalDebtUseCase(
                debts: store, categories: store, settings: store, recorder: recorder,
            ),
            delete: DefaultDeleteDebtUseCase(loans: store, debts: store),
        )
    }

    func makeSplitDetailViewModel(_ transaction: Transaction) -> SplitDetailViewModel {
        // The server only has the ledger of an account that syncs: without one, no link can work.
        let syncs = cloudAccount?.sync?.accountID != nil
        return SplitDetailViewModel(
            transaction: transaction,
            split: DefaultSplitTransactionUseCase(transactions: movements, debts: store),
            useCases: makeDebtsUseCases(),
            web: syncs ? AppEnvironment.current.apiBaseURL : nil,
        )
    }

    func makeSplitBillViewModel(_ transaction: Transaction) -> SplitBillViewModel {
        SplitBillViewModel(
            transaction: transaction,
            split: DefaultSplitTransactionUseCase(transactions: movements, debts: store),
        )
    }
}
