import Domain
import Foundation
import HomeDomain
import SharedPresentation

/// Budgets close to or past their line this month: shown on home and, as notifications, once per
/// category and threshold.
extension HomeViewModel {
    public struct BudgetAlert: Identifiable, Equatable {
        public var id: String {
            categoryID
        }

        public let categoryID: String
        public let category: TransactionCategory?
        public let level: CategoryBudgetStatus.Level
        /// "Groceries is close to its budget".
        public let title: String
        /// "$85.00 spent of $100.00 this month."
        public let body: String
    }

    /// The current month's categories at or past `CategoryBudgetStatus.nearLimitRatio`, closest
    /// to their limit first.
    public var budgetAlerts: [BudgetAlert] {
        guard let overview else { return [] }
        return overview.budgets.compactMap { status in
            guard status.level != .onTrack else { return nil }
            let category = overview.categories.first { $0.id == status.categoryID }
            let name = category.map(CategoryDisplay.name(of:)) ?? status.categoryID
            let spent = formatter.string(status.spent)
            let budget = formatter.string(status.budget)
            return BudgetAlert(
                categoryID: status.categoryID,
                category: category,
                level: status.level,
                title: status.level == .exceeded
                    ? String(localized: "\(name) went over its budget", bundle: #bundle)
                    : String(localized: "\(name) is close to its budget", bundle: #bundle),
                body: String(localized: "\(spent) spent of \(budget) this month.", bundle: #bundle),
            )
        }
    }
}
