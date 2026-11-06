import Domain
import Foundation
import SummaryDomain

extension SummaryViewModel {
    /// What a hidden amount shows, as on Home.
    static let maskedAmount = "••••"

    /// One month-end point of the net worth line.
    struct NetWorthMonth: Identifiable, Equatable {
        let id: Int
        /// Stable x value: two months never share it, unlike their short names across years.
        let key: String
        let label: String
        let value: Double
        let monthName: String
        let text: String
    }

    /// The latest month-end value and how far it moved since the first month shown.
    struct NetWorthSummary: Equatable {
        let amount: String
        let isNegative: Bool
        let caption: String
        let change: String?
        let tone: Tone
    }

    func netWorthMonths(hidden: Bool) -> [NetWorthMonth] {
        guard let report else { return [] }
        let lastYear = report.netWorth.last?.month.year
        return report.netWorth.enumerated().map { index, point in
            let name = monthName(point.month, style: .wide)
            return NetWorthMonth(
                id: index,
                key: point.month.description,
                label: monthName(point.month, style: .abbreviated),
                value: point.total.amount.doubleValue,
                monthName: point.month.year == lastYear ? name : "\(name) \(point.month.year)",
                text: hidden ? Self.maskedAmount : money(point.total.amount),
            )
        }
    }

    func netWorthSummary(hidden: Bool) -> NetWorthSummary? {
        guard let report, let first = report.netWorth.first, let last = report.netWorth.last else { return nil }
        var since = monthName(first.month, style: .wide, capitalized: false)
        if first.month.year != last.month.year {
            since += " \(first.month.year)"
        }
        let change = NetWorthHistory.change(of: report.netWorth)
        let tone: Tone = switch change {
        case let .some(change) where change > 0: .positive
        case let .some(change) where change < 0: .negative
        default: .neutral
        }
        let changeText: String? = change.map { change in
            if change == 0 {
                return String(localized: "No change since \(since)", bundle: #bundle)
            }
            let amount = hidden ? Self.maskedAmount : money(change, sign: .always)
            return String(localized: "\(amount) since \(since)", bundle: #bundle)
        }
        return NetWorthSummary(
            amount: hidden ? Self.maskedAmount : money(last.total.amount),
            isNegative: last.total.amount < 0 && !hidden,
            caption: report.convertsCurrencies
                ? String(localized: "At the end of each month, at today's rate", bundle: #bundle)
                : String(localized: "At the end of each month", bundle: #bundle),
            change: changeText,
            tone: tone,
        )
    }
}
