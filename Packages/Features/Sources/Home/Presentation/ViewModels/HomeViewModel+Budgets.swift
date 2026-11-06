import Domain
import Foundation
import HomeDomain
import SharedPresentation

/// Budgets close to or past their line this month: shown on home and sent as a notification once
/// per category and threshold.
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

    /// How long after scheduling a budget notification arrives: right away, but late enough that
    /// the date is still ahead when the system receives it.
    static let budgetAlertDelay: TimeInterval = 5

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

    /// One notification per alert, identified by category, month and threshold, so the app can
    /// send each one only once even though reminders are rebuilt every time home loads.
    func budgetReminders(_ overview: HomeOverview, now: Date, calendar: Calendar) -> [Reminder] {
        // An overview loaded last month must not warn about last month's spending as if it were now's.
        guard overview.month.month == YearMonth(containing: now, calendar: calendar) else { return [] }
        let month = overview.month.month
        return budgetAlerts.map { alert in
            let threshold = alert.level == .exceeded ? 100 : 80
            return Reminder(
                id: "budget-\(alert.categoryID)-\(month.year)-\(month.month)-\(threshold)",
                kind: .budget(alert.categoryID),
                title: alert.title,
                body: alert.body,
                date: now.addingTimeInterval(Self.budgetAlertDelay),
            )
        }
    }
}
