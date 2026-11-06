import Domain
import Foundation

extension SwiftDataStore {
    /// Writes a whole data set at once: UI tests and simulator runs launch with sample data.
    public func seed(
        settings: Settings,
        accounts: [Account],
        cards: [Card],
        transactions: [Transaction],
        categories: [TransactionCategory],
        recurringRules: [RecurringRule] = [],
        savingsGoals: [SavingsGoal] = [],
        loans: [Loan] = [],
        personalDebts: [PersonalDebt] = [],
        categorizationRules: [CategorizationRule] = [],
    ) throws(DomainError) {
        try save(settings)
        for account in accounts {
            try save(account)
        }
        for card in cards {
            try save(card)
        }
        for transaction in transactions {
            try save(transaction)
        }
        for category in categories {
            try save(category)
        }
        for rule in recurringRules {
            try save(rule)
        }
        for goal in savingsGoals {
            try save(goal)
        }
        for loan in loans {
            try save(loan)
        }
        for debt in personalDebts {
            try save(debt)
        }
        for rule in categorizationRules {
            try save(rule)
        }
    }
}
