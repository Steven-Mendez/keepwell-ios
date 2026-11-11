import Core
import Domain
import Foundation
import GoalsDomain
import Observation
import SharedPresentation

/// Drives "Savings goals": every goal with its progress and the one line that says what to do
/// next, plus the editor and the add/withdraw sheets it opens.
@MainActor
@Observable
public final class GoalsViewModel {
    public enum State: Equatable {
        case loading
        case loaded(SavingsGoalsOverview)
        case failed
    }

    public private(set) var state = State.loading
    /// The open create/edit sheet.
    public var editor: GoalEditorViewModel?
    /// The open "Add money" or "Withdraw" sheet.
    public var amountSheet: GoalAmountViewModel?

    private let getGoals: any GetSavingsGoalsUseCase
    private let saveGoal: any SaveSavingsGoalUseCase
    private let moveMoney: any MoveSavingsGoalMoneyUseCase
    private let deleteGoal: any DeleteSavingsGoalUseCase
    private let calendar: Calendar
    let formatter = CurrencyFormatter()
    static let maskedAmount = "••••"

    public init(
        getGoals: any GetSavingsGoalsUseCase,
        save: any SaveSavingsGoalUseCase,
        moveMoney: any MoveSavingsGoalMoneyUseCase,
        delete: any DeleteSavingsGoalUseCase,
        calendar: Calendar = .current,
    ) {
        self.getGoals = getGoals
        saveGoal = save
        self.moveMoney = moveMoney
        deleteGoal = delete
        self.calendar = calendar
    }

    public var overview: SavingsGoalsOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public var goals: [SavingsGoalProgress] {
        overview?.goals ?? []
    }

    public var isEmpty: Bool {
        overview?.goals.isEmpty == true
    }

    public func load() async {
        do {
            state = try await .loaded(getGoals.execute())
        } catch {
            state = .failed
        }
    }

    // MARK: Sheets

    public func newGoal() {
        guard let overview else { return }
        editor = GoalEditorViewModel(currencies: overview.currencies, currentMonth: overview.currentMonth, save: saveGoal)
    }

    public func edit(_ id: UUID) {
        guard let overview, let progress = overview.progress(of: id) else { return }
        editor = GoalEditorViewModel(
            editing: progress.goal,
            currentMonth: overview.currentMonth,
            save: saveGoal,
            delete: deleteGoal,
        )
    }

    public func addMoney(to id: UUID) {
        guard let goal = overview?.progress(of: id)?.goal else { return }
        amountSheet = GoalAmountViewModel(goal: goal, action: .add, moveMoney: moveMoney)
    }

    public func withdraw(from id: UUID) {
        guard let goal = overview?.progress(of: id)?.goal else { return }
        amountSheet = GoalAmountViewModel(goal: goal, action: .withdraw, moveMoney: moveMoney)
    }

    /// Called after a sheet saved, deleted or moved money, so the list shows the stored result.
    public func sheetFinished() async {
        editor = nil
        amountSheet = nil
        await load()
    }

    // MARK: Rows

    /// The bar never draws past full, even when the goal was overshot.
    public func barFraction(_ progress: SavingsGoalProgress) -> Double {
        min(max(NSDecimalNumber(decimal: progress.fraction).doubleValue, 0), 1)
    }

    /// "38%": how far along the goal is, capped at 100 like the bar.
    public func percent(_ progress: SavingsGoalProgress) -> String {
        barFraction(progress).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "C$4,500.00 of C$15,000.00".
    public func amounts(_ progress: SavingsGoalProgress, hidden: Bool) -> String {
        let saved = money(progress.goal.saved, progress, hidden: hidden)
        let target = money(progress.goal.target.amount, progress, hidden: hidden)
        return String(localized: "\(saved) of \(target)", bundle: #bundle)
    }

    /// What to do next: the monthly figure, "Goal reached", that the date passed, or what's missing.
    public func hint(_ progress: SavingsGoalProgress, hidden: Bool) -> String {
        let remaining = money(progress.remaining, progress, hidden: hidden)
        if progress.isReached {
            return String(localized: "Goal reached", bundle: #bundle)
        }
        if progress.isOverdue {
            return String(localized: "The date passed with \(remaining) to go", bundle: #bundle)
        }
        if let monthly = progress.monthlyAmount, let monthsLeft = progress.monthsLeft, let target = progress.goal.targetMonth {
            let amount = money(monthly, progress, hidden: hidden)
            if monthsLeft == 1 {
                return String(localized: "Set aside \(amount) this month", bundle: #bundle)
            }
            let month = GoalDates.monthAndYear(target, calendar: calendar)
            return String(localized: "Set aside \(amount) a month until \(month)", bundle: #bundle)
        }
        return String(localized: "\(remaining) to go", bundle: #bundle)
    }

    private func money(_ amount: Decimal, _ progress: SavingsGoalProgress, hidden: Bool) -> String {
        hidden ? Self.maskedAmount : formatter.string(from: amount, currencyCode: progress.goal.target.currency)
    }
}

/// How a target month reads to the person.
enum GoalDates {
    /// "December 2026", "diciembre de 2026": the locale writes the month and year as it would a date.
    static func monthAndYear(_ month: TargetMonth, calendar: Calendar) -> String {
        guard let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else {
            return "\(month.month)/\(month.year)"
        }
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// The month name standing alone ("December"), for the month picker.
    static func monthName(_ month: Int, calendar: Calendar) -> String {
        guard let date = calendar.date(from: DateComponents(year: 2000, month: month, day: 1)) else { return "\(month)" }
        var style = Date.FormatStyle.dateTime.month(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
