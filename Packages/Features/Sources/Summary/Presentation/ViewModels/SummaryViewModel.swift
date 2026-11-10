import Core
import Domain
import Foundation
import Observation
import SummaryDomain

@MainActor
@Observable
public final class SummaryViewModel {
    public enum State: Equatable {
        case loading
        case loaded(SummaryReport)
        case failed
    }

    /// The three questions the summary answers: did I save, where did it go, am I on track.
    public enum Chart: Hashable, Sendable, CaseIterable {
        case cashFlow
        case categories
        case pace
    }

    /// The categories chart shows either side of the money.
    public enum Mode: Hashable, Sendable {
        case expenses
        case income
    }

    /// Whether a number is good news, bad news or neither; the view picks the colors.
    public enum Tone: Hashable, Sendable {
        case positive
        case negative
        case neutral
    }

    public private(set) var state = State.loading
    public var chart = Chart.cashFlow
    public var mode = Mode.expenses
    /// Index into `report.months`; the current month until the person picks another.
    public var selectedIndex = DefaultGetSummaryReportUseCase.monthCount - 1

    private let getReport: any GetSummaryReportUseCase
    let calendar: Calendar
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

    func title(of chart: Chart) -> String {
        switch chart {
        case .cashFlow: String(localized: "Cash flow", bundle: #bundle)
        case .categories: String(localized: "Categories", bundle: #bundle)
        case .pace: String(localized: "Pace", bundle: #bundle)
        }
    }

    // MARK: Month

    var selected: MonthlySummary? {
        guard let report, report.months.indices.contains(selectedIndex) else { return nil }
        return report.months[selectedIndex]
    }

    var canSelectPrevious: Bool {
        selectedIndex > 0
    }

    var canSelectNext: Bool {
        selectedIndex < (report?.months.count ?? 0) - 1
    }

    func selectPrevious() {
        if canSelectPrevious {
            selectedIndex -= 1
        }
    }

    func selectNext() {
        if canSelectNext {
            selectedIndex += 1
        }
    }

    /// "November", or "December 2025" once the window reaches into another year.
    var selectedMonthTitle: String {
        guard let selected, let current = report?.months.last?.month else { return "" }
        guard let start = selected.month.dateInterval(in: calendar)?.start else { return selected.month.description }
        let name = selected.month.year == current.year
            ? start.formatted(.dateTime.month(.wide))
            : start.formatted(.dateTime.month(.wide).year())
        return name.sentenceCased
    }

    // MARK: Formatting

    func money(_ amount: Decimal, sign: CurrencyFormatter.Sign = .automatic) -> String {
        formatter.string(from: amount, currencyCode: report?.currency ?? "USD", sign: sign)
    }

    /// Whole units for axis labels and chart annotations, where cents are noise.
    func compactMoney(_ amount: Decimal, sign: CurrencyFormatter.Sign = .automatic) -> String {
        formatter.string(from: amount, currencyCode: report?.currency ?? "USD", fractionDigits: 0, sign: sign)
    }

    func percent(_ share: Decimal) -> String {
        "\(formatter.number(share * 100, fractionDigits: 0))%"
    }

    /// Mid-sentence the month keeps its language's own case ("Spent in October", "Gastado en
    /// octubre"); standing alone, as an axis label, it starts with a capital.
    func monthName(_ month: YearMonth, style: Date.FormatStyle.Symbol.Month, capitalized: Bool = true) -> String {
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
