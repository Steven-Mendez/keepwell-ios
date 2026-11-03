import Domain
import Foundation
import SummaryDomain

extension SummaryViewModel {
    /// One month of the income-vs-spending chart.
    struct FlowMonth: Identifiable, Equatable {
        let id: Int
        /// Stable x value: two months never share it, unlike their short names across years.
        let key: String
        let label: String
        let income: Double
        let expense: Double
        let net: Double
        let netLabel: String
        let tone: Tone
        let monthName: String
        let incomeText: String
        let expenseText: String
        let netText: String
        let incomeLabel: String
        let expenseLabel: String
    }

    var flowMonths: [FlowMonth] {
        guard let report else { return [] }
        return report.months.enumerated().map { index, month in
            let tone = tone(of: month.outcome)
            return FlowMonth(
                id: index,
                key: month.month.description,
                label: monthName(month.month, style: .abbreviated),
                income: month.income.doubleValue,
                expense: month.expense.doubleValue,
                net: month.savings.doubleValue,
                netLabel: month.outcome == .noActivity ? "" : compactMoney(month.savings, sign: .always),
                tone: tone,
                monthName: monthName(month.month, style: .wide),
                incomeText: money(month.income),
                expenseText: money(month.expense),
                netText: outcomeSentence(month.outcome),
                incomeLabel: String(localized: "\(monthName(month.month, style: .wide)), came in", bundle: #bundle),
                expenseLabel: String(localized: "\(monthName(month.month, style: .wide)), went out", bundle: #bundle),
            )
        }
    }

    func selectMonth(key: String) {
        if let index = report?.months.firstIndex(where: { $0.month.description == key }) {
            selectedIndex = index
        }
    }

    /// "Saved in November +$60.00 · You kept 60% of what came in."
    struct FlowHeadline: Equatable {
        let title: String
        let amount: String
        let detail: String?
        let tone: Tone
    }

    var flowHeadline: FlowHeadline? {
        guard let selected else { return nil }
        let month = monthName(selected.month, style: .wide, capitalized: false)
        switch selected.outcome {
        case let .saved(amount):
            let rate = selected.savingsRate.map { percent($0) } ?? ""
            return FlowHeadline(
                title: String(localized: "You saved in \(month)", bundle: #bundle),
                amount: money(amount, sign: .always),
                detail: String(localized: "You kept \(rate) of what came in.", bundle: #bundle),
                tone: .positive,
            )
        case let .overspent(amount):
            let excess = money(amount)
            return FlowHeadline(
                title: String(localized: "You overspent in \(month)", bundle: #bundle),
                amount: money(-amount),
                detail: selected.income > 0
                    ? String(localized: "You spent \(excess) more than came in.", bundle: #bundle)
                    : String(localized: "Nothing came in, so all of it came from your savings.", bundle: #bundle),
                tone: .negative,
            )
        case .even:
            return FlowHeadline(
                title: String(localized: "You broke even in \(month)", bundle: #bundle),
                amount: money(0),
                detail: String(localized: "You spent exactly what came in.", bundle: #bundle),
                tone: .neutral,
            )
        case .noActivity:
            return FlowHeadline(
                title: String(localized: "Nothing moved in \(month)", bundle: #bundle),
                amount: money(0),
                detail: nil,
                tone: .neutral,
            )
        }
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
            income: money(selected.income, sign: .always),
            expense: money(selected.expense),
            incomeFraction: largest > 0 ? (selected.income / largest).doubleValue : 0,
            expenseFraction: largest > 0 ? (selected.expense / largest).doubleValue : 0,
        )
    }

    /// The whole window in one line, so one bad month reads in context.
    struct WindowSummary: Equatable {
        let title: String
        let amount: String
        let detail: String
        let tone: Tone
    }

    var windowSummary: WindowSummary? {
        guard let report else { return nil }
        let trend = report.cashFlow
        let count = report.months.count
        let title = String(localized: "Last \(count) months", bundle: #bundle)
        let detail = String(localized: "You saved in \(trend.monthsSaved) of \(count) months", bundle: #bundle)
        switch trend.outcome {
        case let .saved(amount):
            return WindowSummary(title: title, amount: money(amount, sign: .always), detail: detail, tone: .positive)
        case let .overspent(amount):
            return WindowSummary(title: title, amount: money(-amount), detail: detail, tone: .negative)
        case .even, .noActivity:
            return WindowSummary(title: title, amount: money(0), detail: detail, tone: .neutral)
        }
    }

    func tone(of outcome: CashFlowOutcome) -> Tone {
        switch outcome {
        case .saved: .positive
        case .overspent: .negative
        case .even, .noActivity: .neutral
        }
    }

    private func outcomeSentence(_ outcome: CashFlowOutcome) -> String {
        switch outcome {
        case let .saved(amount):
            String(localized: "saved \(money(amount))", bundle: #bundle)
        case let .overspent(amount):
            String(localized: "overspent \(money(amount))", bundle: #bundle)
        case .even:
            String(localized: "broke even", bundle: #bundle)
        case .noActivity:
            String(localized: "no movements", bundle: #bundle)
        }
    }
}
