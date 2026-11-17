import Domain
import Foundation
import RecurringDomain
import RecurringPresentation

extension AppContainer {
    func makeRecurringRuleDetailViewModel(ruleID: UUID) -> RecurringRuleDetailViewModel {
        RecurringRuleDetailViewModel(
            ruleID: ruleID,
            getOverview: makeGetRecurringOverview(),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: movements, accounts: store),
            setPaused: DefaultSetRecurringRulePausedUseCase(rules: store, materialize: makeMaterializeRecurring()),
            linkPayment: DefaultLinkRecurringPaymentUseCase(rules: store, transactions: movements),
            undo: movementUndo,
        )
    }

    func makeRecurringRulePickerViewModel(transaction: Domain.Transaction) -> RecurringRulePickerViewModel {
        RecurringRulePickerViewModel(
            transaction: transaction,
            getOverview: makeGetRecurringOverview(),
            linkPayment: DefaultLinkRecurringPaymentUseCase(rules: store, transactions: movements),
        )
    }
}
