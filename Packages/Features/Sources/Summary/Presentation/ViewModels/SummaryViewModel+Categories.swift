import Domain
import Foundation
import SharedPresentation
import SummaryDomain

extension SummaryViewModel {
    /// One slice of the ring and its row in the list under it, so both always agree.
    public struct CategoryRow: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let amount: String
        public let percent: String
        public let share: Double
        /// `nil` for the grouped slice and for an id no category has any more (an old import).
        public let category: TransactionCategory?
        /// The grouped "N more" slice, drawn in a neutral color.
        public let isOthers: Bool
        /// Against the comparison period; only in a range.
        var change: Change?

        struct Change: Equatable {
            let text: String
            let tone: SummaryViewModel.Tone
            /// "Before: $20.00", read as a hint; `nil` for a category that is new.
            let before: String?
        }
    }

    var breakdown: CategoryBreakdown? {
        guard let report else { return nil }
        let breakdowns = mode == .expenses ? report.expenseBreakdowns : report.incomeBreakdowns
        return breakdowns.indices.contains(selectedIndex) ? breakdowns[selectedIndex] : nil
    }

    var categoryRows: [CategoryRow] {
        guard let breakdown, let report else { return [] }
        return breakdown.entries.map { entry in
            switch entry.slice {
            case let .category(id):
                let category = report.categories.first { $0.id == id }
                return CategoryRow(
                    id: id,
                    name: category.map(CategoryDisplay.name(of:)) ?? id,
                    amount: money(entry.amount),
                    percent: percent(entry.share),
                    share: entry.share.doubleValue,
                    category: category,
                    isOthers: false,
                )
            case let .others(count):
                return CategoryRow(
                    id: "others",
                    name: String(localized: "\(count) more categories", bundle: #bundle),
                    amount: money(entry.amount),
                    percent: percent(entry.share),
                    share: entry.share.doubleValue,
                    category: nil,
                    isOthers: true,
                )
            }
        }
    }

    /// What the middle of the ring says: the month's total and what it is.
    var ringCenter: (amount: String, caption: String)? {
        guard let breakdown, !breakdown.isEmpty else { return nil }
        return (
            money(breakdown.total),
            mode == .expenses ? String(localized: "spent", bundle: #bundle) : String(localized: "received", bundle: #bundle),
        )
    }

    var categoryCount: String {
        guard let selected else { return "" }
        let count = (mode == .expenses ? selected.categories : selected.incomeCategories).count
        if count == 0 {
            return mode == .expenses ? String(localized: "No spending", bundle: #bundle) : String(localized: "No income", bundle: #bundle)
        }
        return String(localized: "\(count) categories", bundle: #bundle)
    }

    var categoriesEmptyMessage: String {
        let month = selected.map { monthName($0.month, style: .wide, capitalized: false) } ?? ""
        return mode == .expenses
            ? String(localized: "Nothing spent in \(month).", bundle: #bundle)
            : String(localized: "Nothing came in during \(month).", bundle: #bundle)
    }
}
