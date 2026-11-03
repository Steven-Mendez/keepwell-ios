import Core
import Domain
import Foundation
import Observation
import SharedPresentation
import SummaryDomain

@MainActor
@Observable
public final class SummaryViewModel {
    public enum State: Equatable {
        case loading
        case loaded(SummaryReport)
        case failed
    }

    /// The header switch: the chart and the category list follow it.
    public enum Mode: Hashable, Sendable {
        case expenses
        case income
    }

    public struct Bar: Identifiable, Equatable {
        public let id: Int
        public let label: String
        public let accessibilityLabel: String
        /// Height relative to the tallest bar (0…1); 0 when the month had nothing.
        public let fraction: Double
        public let isEmpty: Bool
    }

    public struct CategoryRow: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let amount: String
        public let percent: String
        public let share: Double
        public let colorID: String
    }

    public private(set) var state = State.loading
    public var mode = Mode.expenses
    /// Index into `report.months`; the current month until the person taps another bar.
    public var selectedIndex = DefaultGetSummaryReportUseCase.monthCount - 1

    /// The category list shows the largest ones only, as the design does.
    static let maxCategories = 6

    private let getReport: any GetSummaryReportUseCase
    private let calendar: Calendar
    let formatter = CurrencyFormatter()

    public init(getReport: any GetSummaryReportUseCase, calendar: Calendar = .current) {
        self.getReport = getReport
        self.calendar = calendar
    }

    public var report: SummaryReport? {
        if case let .loaded(report) = state {
            report
        } else {
            nil
        }
    }

    public func load() async {
        do {
            let report = try await getReport.execute()
            state = .loaded(report)
            selectedIndex = min(selectedIndex, max(report.months.count - 1, 0))
        } catch {
            state = .failed
        }
    }

    /// Confirmed income or spending in any month; without it the summary has nothing to compare.
    public var hasMovements: Bool {
        report.map { $0.averageExpense != nil || $0.averageIncome != nil } ?? false
    }

    var emptyMessage: String {
        String(
            localized: "Once you log expenses and income, you will see what came in, what went out and what you spent it on.",
            bundle: #bundle,
        )
    }

    var selected: MonthlySummary? {
        guard let report, report.months.indices.contains(selectedIndex) else { return nil }
        return report.months[selectedIndex]
    }

    private func total(_ month: MonthlySummary) -> Decimal {
        mode == .expenses ? month.expense : month.income
    }

    private var average: Decimal? {
        mode == .expenses ? report?.averageExpense : report?.averageIncome
    }

    /// The tallest value the chart scales to, average included so its line never leaves the chart.
    private var chartMax: Decimal {
        let totals = report?.months.map(total) ?? []
        return max(totals.max() ?? 0, average ?? 0)
    }

    var bars: [Bar] {
        guard let report else { return [] }
        let top = chartMax
        return report.months.enumerated().map { index, month in
            let value = total(month)
            let name = monthName(month.month, style: .wide)
            return Bar(
                id: index,
                label: monthName(month.month, style: .abbreviated),
                accessibilityLabel: "\(name): \(money(value))",
                fraction: top > 0 ? (value / top).doubleValue : 0,
                isEmpty: value == 0,
            )
        }
    }

    /// Where the dashed average line sits (0…1 of the chart), with its label.
    var averageLine: (fraction: Double, label: String, caption: String)? {
        guard let average, average > 0 else { return nil }
        let top = chartMax
        let amount = money(average)
        return (
            top > 0 ? (average / top).doubleValue : 0,
            formatter.string(from: average, currencyCode: report?.currency ?? "USD", fractionDigits: 0),
            String(localized: "Average \(amount) / month", bundle: #bundle),
        )
    }

    var headline: (title: String, amount: String)? {
        guard let selected else { return nil }
        let month = monthName(selected.month, style: .wide, capitalized: false)
        let title = mode == .expenses
            ? String(localized: "Spent in \(month)", bundle: #bundle)
            : String(localized: "Received in \(month)", bundle: #bundle)
        return (title, money(total(selected)))
    }

    /// Income and spending of the selected month, each as a fraction of the larger.
    struct Flow: Equatable {
        let income: String
        let expense: String
        let incomeFraction: Double
        let expenseFraction: Double
    }

    var flow: Flow? {
        guard let selected else { return nil }
        let largest = max(selected.income, selected.expense)
        return Flow(
            income: formatter.string(from: selected.income, currencyCode: selected.currency, sign: .always),
            expense: money(selected.expense),
            incomeFraction: largest > 0 ? (selected.income / largest).doubleValue : 0,
            expenseFraction: largest > 0 ? (selected.expense / largest).doubleValue : 0,
        )
    }

    var savings: (amount: String, rate: String, isNegative: Bool)? {
        guard let selected else { return nil }
        let rate = if let savingsRate = selected.savingsRate {
            String(localized: "\(formatter.number(savingsRate * 100, fractionDigits: 0))% of what came in", bundle: #bundle)
        } else {
            String(localized: "No income", bundle: #bundle)
        }
        return (money(selected.savings), rate, selected.savings < 0)
    }

    var categoryRows: [CategoryRow] {
        guard let selected, let report else { return [] }
        let totals = mode == .expenses ? selected.categories : selected.incomeCategories
        return totals.prefix(Self.maxCategories).map { total in
            let category = report.categories.first { $0.id == total.categoryID }
            return CategoryRow(
                id: total.categoryID,
                name: category.map(CategoryDisplay.name(of:)) ?? total.categoryID,
                amount: money(total.amount),
                percent: "\(formatter.number(total.share * 100, fractionDigits: 0))%",
                share: total.share.doubleValue,
                colorID: total.categoryID,
            )
        }
    }

    var categoryCount: String {
        guard let selected else { return "" }
        let count = (mode == .expenses ? selected.categories : selected.incomeCategories).count
        if count == 0 {
            return mode == .expenses ? String(localized: "No spending", bundle: #bundle) : String(localized: "No income", bundle: #bundle)
        }
        return String(localized: "\(count) categories", bundle: #bundle)
    }

    private func money(_ amount: Decimal) -> String {
        formatter.string(from: amount, currencyCode: report?.currency ?? "USD")
    }

    /// Mid-sentence the month keeps its language's own case ("Spent in October", "Gastado en
    /// octubre"); standing alone, as a bar label, it starts with a capital.
    private func monthName(_ month: YearMonth, style: Date.FormatStyle.Symbol.Month, capitalized: Bool = true) -> String {
        guard let start = month.dateInterval(in: calendar)?.start else { return month.description }
        let name = start.formatted(.dateTime.month(style))
        return capitalized ? name.localizedCapitalized : name
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
