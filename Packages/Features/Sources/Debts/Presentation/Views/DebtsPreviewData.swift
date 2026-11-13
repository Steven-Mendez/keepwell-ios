import CreateTransactionDomain
import DebtsDomain
import Domain
import DomainSamples
import Foundation
import SwiftUI

/// Screens wired to the sample data in memory, for `#Preview` and tests.
@MainActor
public enum DebtsPreview {
    public static func useCases(
        store: InMemoryStore = InMemoryStore(sample: .standard),
        now: Date = SampleData.defaultReferenceDate,
    ) -> DebtsUseCases {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store,
        )
        let recorder = InstallmentMovementRecorder(prepare: DefaultPrepareTransactionUseCase(context: context))
        return DebtsUseCases(
            getDebts: DefaultGetDebtsUseCase(loans: store, debts: store, settings: store, now: { now }),
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

    public static func listViewModel(
        store: InMemoryStore = InMemoryStore(sample: .standard),
        now: Date = SampleData.defaultReferenceDate,
    ) -> DebtsViewModel {
        DebtsViewModel(useCases: useCases(store: store, now: now), now: { now })
    }

    static func list() -> some View {
        DebtsView(viewModel: listViewModel(), onBack: {})
    }
}
