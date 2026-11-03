import Domain
import Foundation
import SummaryDomain

extension SummaryViewModel {
    struct PacePoint: Identifiable, Equatable {
        enum Series: Hashable {
            case selected
            case previous
        }

        var id: String {
            "\(series)-\(day)"
        }

        let series: Series
        let day: Int
        let cumulative: Double
    }

    struct PaceSummary: Equatable {
        let title: String
        let amount: String
        /// "$10.00 less than October by the same day"; `nil` when there is nothing to compare.
        let comparison: String?
        let tone: Tone
        let currentLegend: String
        let previousLegend: String
        let previousTotal: String
        /// The x axis runs to the longer of the two months.
        let dayCount: Int
        let accessibilitySummary: String
    }

    var pace: SpendingPace? {
        guard let report, report.paces.indices.contains(selectedIndex) else { return nil }
        return report.paces[selectedIndex]
    }

    var pacePoints: [PacePoint] {
        guard let pace else { return [] }
        return pace.previous.map { PacePoint(series: .previous, day: $0.day, cumulative: $0.cumulative.doubleValue) }
            + pace.current.map { PacePoint(series: .selected, day: $0.day, cumulative: $0.cumulative.doubleValue) }
    }

    var paceSummary: PaceSummary? {
        guard let pace, let report else { return nil }
        let isRunning = selectedIndex == report.months.count - 1
        let month = monthName(pace.month, style: .wide, capitalized: false)
        let previous = monthName(pace.previousMonth, style: .wide, capitalized: false)
        let day = pace.comparisonDay
        let title = isRunning
            ? String(localized: "Spent so far in \(month)", bundle: #bundle)
            : String(localized: "Spent in \(month)", bundle: #bundle)
        let difference = money(abs(pace.difference))
        let (comparison, tone): (String?, Tone) = if pace.previousTotal == 0 {
            (String(localized: "Nothing was spent in \(previous) to compare with.", bundle: #bundle), .neutral)
        } else if pace.difference < 0 {
            (String(localized: "\(difference) less than \(previous) by the same day", bundle: #bundle), .positive)
        } else if pace.difference > 0 {
            (String(localized: "\(difference) more than \(previous) by the same day", bundle: #bundle), .negative)
        } else {
            (String(localized: "Same as \(previous) by the same day", bundle: #bundle), .neutral)
        }
        let spent = money(pace.spentSoFar)
        let previousSpent = money(pace.previousBySameDay)
        return PaceSummary(
            title: title,
            amount: spent,
            comparison: comparison,
            tone: tone,
            currentLegend: monthName(pace.month, style: .wide),
            previousLegend: monthName(pace.previousMonth, style: .wide),
            previousTotal: String(
                localized: "\(monthName(pace.previousMonth, style: .wide)) total: \(money(pace.previousTotal))",
                bundle: #bundle,
            ),
            dayCount: max(pace.previous.count, Self.daysIn(pace.month, calendar: calendar)),
            accessibilitySummary: String(
                localized: "By day \(day), \(spent) spent in \(month) against \(previousSpent) in \(previous).",
                bundle: #bundle,
            ),
        )
    }

    private static func daysIn(_ month: YearMonth, calendar: Calendar) -> Int {
        guard let start = month.dateInterval(in: calendar)?.start else { return 31 }
        return calendar.range(of: .day, in: .month, for: start)?.count ?? 31
    }
}
