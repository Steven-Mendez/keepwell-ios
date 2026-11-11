import Domain
import Foundation
import SharedPresentation
import SummaryDomain

extension SummaryViewModel {
    private var rangeBreakdown: CategoryBreakdown? {
        guard let report = range?.report else { return nil }
        return mode == .expenses ? report.expenseBreakdown : report.incomeBreakdown
    }

    /// Whether the comparison period had any of this side to compare with.
    private var isComparable: Bool {
        guard let report = range?.report, report.hasComparison else { return false }
        return (mode == .expenses ? report.comparisonCashFlow.expense : report.comparisonCashFlow.income) > 0
    }

    private func rangeChange(_ entry: CategoryChange) -> CategoryRow.Change? {
        guard isComparable else { return nil }
        guard entry.previous > 0 else {
            return CategoryRow.Change(text: String(localized: "New", bundle: #bundle), tone: .neutral, before: nil)
        }
        let before = money(entry.previous)
        return CategoryRow.Change(
            text: changePercent(entry.amount, entry.previous) ?? "",
            tone: changeTone(entry.amount, entry.previous, upIsGood: mode == .income),
            before: String(localized: "Before: \(before)", bundle: #bundle),
        )
    }

    /// The ring's slices: the largest categories and the "N more categories" tail.
    var rangeRingRows: [CategoryRow] {
        guard let breakdown = rangeBreakdown else { return [] }
        return breakdown.entries.map { entry in
            switch entry.slice {
            case let .category(id):
                categoryRow(id: id, amount: entry.amount, share: entry.share)
            case let .others(count):
                CategoryRow(
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

    /// The list names every category, not only the ring's largest, so nothing hides in "others".
    var rangeCategoryRows: [CategoryRow] {
        guard let report = range?.report else { return [] }
        let changes = mode == .expenses ? report.expenseCategories : report.incomeCategories
        return changes.filter { $0.amount > 0 }.map { entry in
            var row = categoryRow(id: entry.categoryID, amount: entry.amount, share: entry.share)
            row.change = rangeChange(entry)
            return row
        }
    }

    private func categoryRow(id: String, amount: Decimal, share: Decimal) -> CategoryRow {
        let category = category(id)
        return CategoryRow(
            id: id,
            name: category.map(CategoryDisplay.name(of:)) ?? id,
            amount: money(amount),
            percent: percent(share),
            share: share.doubleValue,
            category: category,
            isOthers: false,
        )
    }

    var rangeRingCenter: (amount: String, caption: String)? {
        guard let breakdown = rangeBreakdown, !breakdown.isEmpty else { return nil }
        return (
            money(breakdown.total),
            mode == .expenses ? String(localized: "spent", bundle: #bundle) : String(localized: "received", bundle: #bundle),
        )
    }

    var rangeCategoriesEmpty: String {
        mode == .expenses ? String(localized: "No spending", bundle: #bundle) : String(localized: "No income", bundle: #bundle)
    }

    var rangeCategoriesCaption: String? {
        guard isComparable, let report = range?.report else { return nil }
        return comparisonLabel(report.comparison)
    }
}
