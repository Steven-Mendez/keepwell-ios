import Core
import Domain
import Foundation
import Observation
import PlanDomain
import SharedPresentation

/// Drives the Plan hub: a summary of recurring movements, savings goals and debts, worded like
/// the screens each card leads to.
@MainActor
@Observable
public final class PlanViewModel {
    public enum State: Equatable {
        case loading
        case loaded(PlanOverview)
        case failed
    }

    public private(set) var state = State.loading

    private let getOverview: any GetPlanOverviewUseCase
    private let calendar: Calendar
    private let now: () -> Date
    private let formatter = CurrencyFormatter()
    static let maskedAmount = "••••"

    public init(getOverview: any GetPlanOverviewUseCase, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.getOverview = getOverview
        self.calendar = calendar
        self.now = now
    }

    public var overview: PlanOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public func load() async {
        do {
            state = try await .loaded(getOverview.execute())
        } catch {
            state = .failed
        }
    }

    // MARK: Recurring

    /// "$41.97", the same figure as the head of the Recurring screen.
    func subscriptionsPerMonth(_ recurring: PlanOverview.Recurring, hidden: Bool) -> String {
        hidden ? Self.maskedAmount : formatter.string(recurring.subscriptionsPerMonth)
    }

    /// "Per month · 7 subscriptions", under the monthly total.
    func subscriptionsCaption(_ recurring: PlanOverview.Recurring) -> String {
        let count = recurring.subscriptionCount
        guard count > 0 else { return String(localized: "Subscriptions per month", bundle: #bundle) }
        return String(localized: "Per month · \(count) subscriptions", bundle: #bundle)
    }

    /// "Not including 1 in EUR", one line per currency the total leaves out. Counts, not amounts,
    /// so they show with amounts hidden too.
    func excludedSubscriptionLines(_ recurring: PlanOverview.Recurring) -> [String] {
        recurring.excluded.map { excluded in
            String(localized: "Not including \(excluded.count) in \(excluded.currency)", bundle: #bundle)
        }
    }

    /// "Next: Netflix · Tomorrow", or `nil` when nothing is scheduled.
    func nextRecurringLine(_ recurring: PlanOverview.Recurring) -> String? {
        guard let next = recurring.next else { return nil }
        let name = next.rule.name
        let day = RecurringDisplay.day(next.date, today: now(), calendar: calendar)
        return String(localized: "Next: \(name) · \(day)", bundle: #bundle)
    }

    // MARK: Goals

    /// "C$4,500.00 of C$15,000.00".
    func goalAmounts(_ progress: SavingsGoalProgress, hidden: Bool) -> String {
        let currency = progress.goal.target.currency
        let saved = hidden ? Self.maskedAmount : formatter.string(from: progress.goal.saved, currencyCode: currency)
        let target = hidden ? Self.maskedAmount : formatter.string(from: progress.goal.target.amount, currencyCode: currency)
        return String(localized: "\(saved) of \(target)", bundle: #bundle)
    }

    /// The bar stops at full even for an overshot goal.
    func goalBarFraction(_ progress: SavingsGoalProgress) -> Double {
        min(max(NSDecimalNumber(decimal: progress.fraction).doubleValue, 0), 1)
    }

    /// "30%".
    func goalPercent(_ progress: SavingsGoalProgress) -> String {
        goalBarFraction(progress).formatted(.percent.precision(.fractionLength(0)))
    }

    func goalCount(_ goals: PlanOverview.Goals) -> String {
        let count = goals.count
        return String(localized: "\(count) goals", bundle: #bundle)
    }

    // MARK: Debts

    /// "C$19,166.70 · US$40.00", one amount per currency, or "Nothing" without any.
    func debtTotal(_ lines: [Money], hidden: Bool) -> String {
        guard !lines.isEmpty else { return String(localized: "Nothing", bundle: #bundle) }
        return lines.map { hidden ? Self.maskedAmount : formatter.string($0) }.joined(separator: " · ")
    }

    /// "3 debts to pay", or "You owe" when there's nothing to count.
    func youOweTitle(_ debts: PlanOverview.Debts) -> String {
        let count = debts.youOweCount
        guard count > 0 else { return String(localized: "You owe", bundle: #bundle) }
        return String(localized: "\(count) debts to pay", bundle: #bundle)
    }

    /// "2 people owe you", or "Owed to you" when nobody does.
    func owedToYouTitle(_ debts: PlanOverview.Debts) -> String {
        let count = debts.peopleOwingCount
        guard count > 0 else { return String(localized: "Owed to you", bundle: #bundle) }
        return String(localized: "\(count) people owe you", bundle: #bundle)
    }

    /// "Next: 3/12 on Nov 28, 2026 · C$5,500.00" or "Overdue: …", `nil` without an open loan.
    func nextInstallmentLine(_ debts: PlanOverview.Debts, hidden: Bool) -> String? {
        guard let progress = debts.nextLoan, let next = progress.next else { return nil }
        let amount = hidden ? Self.maskedAmount : formatter.string(progress.loan.installment)
        let number = "\(next.number)/\(progress.loan.installmentCount)"
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let day = next.dueDate.formatted(style)
        return progress.isNextOverdue
            ? String(localized: "Overdue: \(number) on \(day) · \(amount)", bundle: #bundle)
            : String(localized: "Next: \(number) on \(day) · \(amount)", bundle: #bundle)
    }
}
