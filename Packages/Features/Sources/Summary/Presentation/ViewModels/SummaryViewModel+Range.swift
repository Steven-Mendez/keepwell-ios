import Domain
import Foundation
import SharedPresentation
import SummaryDomain

extension SummaryViewModel {
    /// What `.task(id:)` watches, so a new period or custom span reloads the range.
    struct RangeRequest: Hashable {
        let period: SummaryPeriod
        let custom: MonthRange?
    }

    var rangeRequest: RangeRequest {
        RangeRequest(period: period, custom: customRange)
    }

    var showsRange: Bool {
        period != .month && getRange != nil
    }

    func loadRange() async {
        guard period != .month, let getRange else {
            range = nil
            return
        }
        range = try? await getRange.execute(period: period, custom: customRange)
    }

    func title(of period: SummaryPeriod) -> String {
        switch period {
        case .month: String(localized: "Month", bundle: #bundle)
        case .thisYear: String(localized: "This year", bundle: #bundle)
        case .last12: String(localized: "Last 12 months", bundle: #bundle)
        case .custom: String(localized: "Custom", bundle: #bundle)
        }
    }

    // MARK: Custom pickers

    /// Reaches back to the first movement, and to the span's own start when it comes earlier (the
    /// default custom span), newest first like the web pickers.
    var customMonthOptions: [YearMonth] {
        guard let range else { return [] }
        let first = min(range.report.range.start, range.activity.start)
        return MonthRange(first, range.activity.end).months.reversed()
    }

    func pickerTitle(of month: YearMonth) -> String {
        monthText(month, style: .wide, withYear: true)
    }

    func setCustomStart(_ month: YearMonth) {
        guard let current = range?.report.range else { return }
        customRange = MonthRange(month, current.end)
    }

    func setCustomEnd(_ month: YearMonth) {
        guard let current = range?.report.range else { return }
        customRange = MonthRange(current.start, month)
    }

    // MARK: Text

    func monthText(_ month: YearMonth, style: Date.FormatStyle.Symbol.Month, withYear: Bool) -> String {
        guard let start = month.dateInterval(in: calendar)?.start else { return month.description }
        var format = Date.FormatStyle(calendar: calendar).month(style)
        if withYear {
            format = format.year()
        }
        return start.formatted(format).localizedCapitalized
    }

    /// "Jan – Nov 2026", "March 2026", "Mar 2025 – Aug 2026".
    func rangeText(_ range: MonthRange) -> String {
        let (start, end) = (range.start, range.end)
        if start == end {
            return monthText(start, style: .wide, withYear: true)
        }
        if start.year == end.year {
            return "\(monthText(start, style: .abbreviated, withYear: false)) – \(monthText(end, style: .abbreviated, withYear: false)) \(end.year)"
        }
        return "\(monthText(start, style: .abbreviated, withYear: true)) – \(monthText(end, style: .abbreviated, withYear: true))"
    }

    /// "Mar", or "Mar 25" once the period crosses a year, so two Marches never collide.
    func axisMonth(_ month: YearMonth, multiYear: Bool) -> String {
        let name = monthText(month, style: .abbreviated, withYear: false)
        return multiYear ? "\(name) \(String(format: "%02d", month.year % 100))" : name
    }

    /// "+12%" / "−8%"; `nil` when there is nothing to divide by.
    func changePercent(_ current: Decimal, _ previous: Decimal) -> String? {
        guard previous > 0 else { return nil }
        let rate = (current - previous) / previous
        if rate == 0 {
            return "="
        }
        return "\(rate > 0 ? "+" : "−")\(percent(abs(rate)))"
    }

    /// Spending going up is bad news; income or savings going up is good news.
    func changeTone(_ current: Decimal, _ previous: Decimal, upIsGood: Bool) -> Tone {
        if current == previous {
            return .neutral
        }
        return (current > previous) == upIsGood ? .positive : .negative
    }

    func comparisonLabel(_ range: MonthRange) -> String {
        String(localized: "vs \(rangeText(range))", bundle: #bundle)
    }

    var rangeSubtitle: String {
        guard let report = range?.report else { return "" }
        let text = rangeText(report.range)
        return report.isRunning ? String(localized: "\(text) · through today", bundle: #bundle) : text
    }

    private func isMultiYear(_ report: TrendReport) -> Bool {
        report.range.start.year != report.range.end.year
    }

    // MARK: Tiles

    struct Detail: Equatable {
        let text: String
        let tone: Tone
    }

    struct Tile: Identifiable, Equatable {
        let id: Int
        let label: String
        let value: String
        let caption: String?
        let detail: Detail?
        let tone: Tone
        /// Income and spending carry the chart colors so the tiles read like the bars.
        let dot: Tone?
    }

    var rangeTiles: [Tile] {
        guard let report = range?.report else { return [] }
        let (flow, previous) = (report.cashFlow, report.comparisonCashFlow)
        let net = flow.net
        func versus(_ current: Decimal, _ before: Decimal, upIsGood: Bool) -> Detail? {
            guard report.hasComparison, let change = changePercent(current, before) else { return nil }
            return Detail(text: "\(change) \(comparisonLabel(report.comparison))", tone: changeTone(current, before, upIsGood: upIsGood))
        }
        var savedDetail: Detail?
        let savedChange = net - previous.net
        if report.hasComparison, savedChange != 0 {
            let amount = money(abs(savedChange))
            let against = rangeText(report.comparison)
            savedDetail = Detail(
                text: savedChange > 0
                    ? String(localized: "\(amount) more than \(against)", bundle: #bundle)
                    : String(localized: "\(amount) less than \(against)", bundle: #bundle),
                tone: savedChange > 0 ? .positive : .negative,
            )
        }
        let kept: String? = flow.savingsRate.flatMap { $0 > 0 ? String(
            localized: "You kept \(percent($0)) of what came in",
            bundle: #bundle,
        ) : nil }
        return [
            Tile(
                id: 0,
                label: net < 0 ? String(localized: "You overspent", bundle: #bundle) : String(localized: "You saved", bundle: #bundle),
                value: money(net, sign: net > 0 ? .always : .automatic),
                caption: kept, detail: savedDetail, tone: tone(of: flow.outcome), dot: nil,
            ),
            Tile(
                id: 1, label: String(localized: "Came in", bundle: #bundle), value: money(flow.income),
                caption: nil, detail: versus(flow.income, previous.income, upIsGood: true), tone: .neutral, dot: .positive,
            ),
            Tile(
                id: 2, label: String(localized: "Went out", bundle: #bundle), value: money(flow.expense),
                caption: nil, detail: versus(flow.expense, previous.expense, upIsGood: false), tone: .neutral, dot: .negative,
            ),
            Tile(
                id: 3,
                label: String(localized: "Average spending", bundle: #bundle),
                value: money(report.averageExpense ?? flow.expense),
                caption: String(localized: "per month", bundle: #bundle),
                detail: report.averageIncome.map {
                    Detail(text: String(localized: "Income averages \(money($0))", bundle: #bundle), tone: .neutral)
                },
                tone: .neutral, dot: nil,
            ),
        ]
    }

    // MARK: Month by month

    struct RangeMonth: Identifiable, Equatable {
        let id: Int
        let key: String
        let label: String
        let name: String
        let income: Double
        let expense: Double
        let incomeText: String
        let expenseText: String
        let netText: String
        let tone: Tone
    }

    var rangeMonths: [RangeMonth] {
        guard let report = range?.report else { return [] }
        let many = isMultiYear(report)
        return report.months.enumerated().map { index, month in
            RangeMonth(
                id: index,
                key: month.month.description,
                label: axisMonth(month.month, multiYear: many),
                name: monthText(month.month, style: .wide, withYear: true),
                income: month.income.doubleValue,
                expense: month.expense.doubleValue,
                incomeText: money(month.income),
                expenseText: money(month.expense),
                netText: money(month.savings, sign: .always),
                tone: tone(of: month.outcome),
            )
        }
    }

    var rangeAverage: AverageSpending? {
        guard let average = range?.report.averageExpense, average > 0 else { return nil }
        return AverageSpending(value: average.doubleValue, text: String(localized: "Average \(money(average)) / month", bundle: #bundle))
    }

    /// At most about six x-axis labels, always including the last month, so a year of months fits
    /// on a phone.
    func axisKeys(_ keys: [String]) -> [String] {
        let step = max(1, Int((Double(keys.count) / 6).rounded(.up)))
        return keys.enumerated().filter { $0.offset.isMultiple(of: step) || $0.offset == keys.count - 1 }.map(\.element)
    }

    // MARK: Savings over time

    struct SavingsPoint: Identifiable, Equatable {
        let id: Int
        let key: String
        let label: String
        let name: String
        let current: Double
        let currentText: String
        let previous: Double?
        let previousText: String?
    }

    var savingsPoints: [SavingsPoint] {
        guard let report = range?.report else { return [] }
        let many = isMultiYear(report)
        return report.months.indices.map { index in
            let month = report.months[index].month
            let before = report.hasComparison ? report.comparisonCumulativeSavings[index] : nil
            return SavingsPoint(
                id: index,
                key: month.description,
                label: axisMonth(month, multiYear: many),
                name: monthText(month, style: .wide, withYear: true),
                current: report.cumulativeSavings[index].doubleValue,
                currentText: money(report.cumulativeSavings[index], sign: .always),
                previous: before?.doubleValue,
                previousText: before.map { money($0, sign: .always) },
            )
        }
    }

    var savingsTotal: String? {
        range?.report.cumulativeSavings.last.map { money($0, sign: .always) }
    }

    var hasComparison: Bool {
        range?.report.hasComparison ?? false
    }

    var currentLegend: String {
        range.map { rangeText($0.report.range) } ?? ""
    }

    var comparisonLegend: String {
        range.map { rangeText($0.report.comparison) } ?? ""
    }

    // MARK: Top categories over time

    struct CategorySeries: Identifiable, Equatable {
        let id: String
        let name: String
        let category: TransactionCategory?
    }

    struct CategoryPoint: Identifiable, Equatable {
        let id: String
        let seriesID: String
        let key: String
        let name: String
        let amount: Double
        let amountText: String
    }

    func category(_ id: String) -> TransactionCategory? {
        report?.categories.first { $0.id == id }
    }

    func categoryName(_ id: String) -> String {
        category(id).map(CategoryDisplay.name(of:)) ?? id
    }

    var categorySeries: [CategorySeries] {
        range?.report.categoryTrends.map { CategorySeries(
            id: $0.categoryID,
            name: categoryName($0.categoryID),
            category: category($0.categoryID),
        ) } ?? []
    }

    var categoryPoints: [CategoryPoint] {
        guard let report = range?.report else { return [] }
        return report.categoryTrends.flatMap { trend in
            report.months.indices.map { index in
                let month = report.months[index].month
                return CategoryPoint(
                    id: "\(trend.categoryID)-\(month)",
                    seriesID: trend.categoryID,
                    key: month.description,
                    name: categoryName(trend.categoryID),
                    amount: trend.amounts[index].doubleValue,
                    amountText: money(trend.amounts[index]),
                )
            }
        }
    }

    var categoryAxisLabels: [String: String] {
        guard let report = range?.report else { return [:] }
        let many = isMultiYear(report)
        return Dictionary(uniqueKeysWithValues: report.months.map { ($0.month.description, axisMonth($0.month, multiYear: many)) })
    }

    // MARK: Highlights

    struct Highlight: Identifiable, Equatable {
        let id: Int
        let label: String
        let value: String
        let detail: String?
        let tone: Tone
    }

    var highlights: [Highlight] {
        guard let report = range?.report else { return [] }
        var items: [Highlight] = []
        func add(_ label: String, _ value: String, _ detail: String?, _ tone: Tone) {
            items.append(Highlight(id: items.count, label: label, value: value, detail: detail, tone: tone))
        }
        let many = isMultiYear(report)
        if let best = report.bestMonth {
            add(
                String(localized: "Best month", bundle: #bundle),
                monthText(best.month, style: .wide, withYear: many),
                money(best.savings, sign: .always),
                best.savings > 0 ? .positive : .neutral,
            )
        }
        if let worst = report.worstMonth {
            add(
                String(localized: "Toughest month", bundle: #bundle),
                monthText(worst.month, style: .wide, withYear: many),
                money(worst.savings, sign: worst.savings > 0 ? .always : .automatic),
                worst.savings < 0 ? .negative : .neutral,
            )
        }
        let active = report.activeMonthCount
        if active > 0 {
            add(
                String(localized: "Months you saved", bundle: #bundle),
                String(localized: "\(report.cashFlow.monthsSaved) of \(active)", bundle: #bundle),
                nil, .neutral,
            )
        }
        if let grew = report.biggestIncrease {
            add(String(localized: "Grew the most", bundle: #bundle), categoryName(grew.categoryID), "+\(money(grew.change))", .negative)
        }
        if let dropped = report.biggestDecrease {
            add(
                String(localized: "Dropped the most", bundle: #bundle),
                categoryName(dropped.categoryID),
                "−\(money(abs(dropped.change)))",
                .positive,
            )
        }
        return items
    }

    var highlightsCaption: String? {
        guard let report = range?.report, report.hasComparison,
              report.biggestIncrease != nil || report.biggestDecrease != nil else { return nil }
        return String(localized: "Spending changes \(comparisonLabel(report.comparison))", bundle: #bundle)
    }

    // MARK: Year over year

    struct YearBar: Identifiable, Equatable {
        let id: Int
        let label: String
        let income: Double
        let expense: Double
        let net: Double
        let incomeText: String
        let expenseText: String
        let netText: String
        let tone: Tone
    }

    var yearBars: [YearBar] {
        range?.years.map { year in
            let net = year.cashFlow.net
            return YearBar(
                id: year.year,
                label: year.isRunning ? String(localized: "\(year.year) so far", bundle: #bundle) : String(year.year),
                income: year.cashFlow.income.doubleValue,
                expense: year.cashFlow.expense.doubleValue,
                net: net.doubleValue,
                incomeText: money(year.cashFlow.income),
                expenseText: money(year.cashFlow.expense),
                netText: money(net, sign: net > 0 ? .always : .automatic),
                tone: tone(of: year.cashFlow.outcome),
            )
        } ?? []
    }
}
