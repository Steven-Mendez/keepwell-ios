import Domain
import Foundation
import SharedPresentation
import SummaryDomain

extension SummaryViewModel {
    /// One budgeted category in the selected month, worded and ready to draw.
    public struct BudgetRow: Identifiable, Equatable {
        public let id: String
        public let name: String
        /// `nil` for an id no category has any more.
        public let category: TransactionCategory?
        /// "$80.00 of $100.00".
        public let progress: String
        /// "$20.00 left" or "$15.00 over".
        public let remaining: String
        /// Spent over budget; the bar clamps it to a full bar.
        public let fraction: Double
        public let level: CategoryBudgetStatus.Level
    }

    var budgetRows: [BudgetRow] {
        guard let report, report.budgets.indices.contains(selectedIndex) else { return [] }
        return report.budgets[selectedIndex].map { status in
            let category = report.categories.first { $0.id == status.categoryID }
            let spent = money(status.spent.amount)
            let budget = money(status.budget.amount)
            let left = money(abs(status.remaining))
            return BudgetRow(
                id: status.categoryID,
                name: category.map(CategoryDisplay.name(of:)) ?? status.categoryID,
                category: category,
                progress: String(localized: "\(spent) of \(budget)", bundle: #bundle),
                remaining: status.remaining < 0
                    ? String(localized: "\(left) over", bundle: #bundle)
                    : String(localized: "\(left) left", bundle: #bundle),
                fraction: status.ratio.doubleValue,
                level: status.level,
            )
        }
    }

    /// "2 budgets are in NIO and aren't compared", one line per other currency: the budgets
    /// `budgetRows` leaves out, named instead of converted at a rate picked today.
    var otherCurrencyBudgetNotes: [String] {
        (report?.otherCurrencyBudgets ?? []).map { group in
            String(localized: "\(group.count) budgets are in \(group.currency) and aren't compared", bundle: #bundle)
        }
    }
}
