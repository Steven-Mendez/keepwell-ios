import Domain
import Foundation
import HomeDomain

/// The debts card and the installment reminders.
extension HomeViewModel {
    /// The loan whose next installment comes first, if any is still open.
    func nextLoan(_ overview: HomeOverview) -> LoanProgress? {
        overview.loans.first { $0.next != nil }
    }

    /// "Motorbike · 3/12 on Nov 28, 2026 · C$5,500.00", masked with the rest of home's amounts.
    func installmentLine(_ progress: LoanProgress, hidden: Bool) -> String? {
        guard let next = progress.next else { return nil }
        let amount = visible(
            formatter.string(from: progress.loan.installmentAmount, currencyCode: progress.loan.borrowed.currency),
            hidden: hidden,
        )
        let day = next.dueDate.formatted(Self.dayStyle(calendar))
        return String(
            localized: "\(progress.loan.name) · \(next.number)/\(progress.loan.installmentCount) on \(day) · \(amount)",
            bundle: #bundle,
        )
    }

    /// One amount per currency, or `nil` without any.
    func debtTotal(_ lines: [Money], hidden: Bool) -> String? {
        guard !lines.isEmpty else { return nil }
        return lines.map { visible(formatter.string(from: $0.amount, currencyCode: $0.currency), hidden: hidden) }.joined(separator: " · ")
    }

    static func dayStyle(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}
