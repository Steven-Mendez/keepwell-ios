import Domain
import Foundation

public protocol GetSavingsGoalsUseCase: Sendable {
    func execute() async throws(DomainError) -> SavingsGoalsOverview
}

public struct DefaultGetSavingsGoalsUseCase: GetSavingsGoalsUseCase {
    private let goals: any SavingsGoalRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        goals: any SavingsGoalRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.goals = goals
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> SavingsGoalsOverview {
        let currencies = try await settings.load()?.currencies ?? .initial
        return try await SavingsGoalsOverview(
            currencies: currencies,
            currentMonth: YearMonth(containing: now(), calendar: calendar),
            goals: goals.fetchSavingsGoals(),
        )
    }
}

/// Creates or edits a goal. A new goal starts with nothing set aside, in the principal or second
/// currency; an edit keeps what is set aside and the currency the goal was created in, because
/// the money already put away was counted in it.
public protocol SaveSavingsGoalUseCase: Sendable {
    @discardableResult
    func execute(_ draft: SavingsGoalDraft) async throws(DomainError) -> SavingsGoal
}

public struct DefaultSaveSavingsGoalUseCase: SaveSavingsGoalUseCase {
    private let goals: any SavingsGoalRepository
    private let settings: any SettingsRepository
    private let makeID: @Sendable () -> UUID

    public init(
        goals: any SavingsGoalRepository,
        settings: any SettingsRepository,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        self.goals = goals
        self.settings = settings
        self.makeID = makeID
    }

    public func execute(_ draft: SavingsGoalDraft) async throws(DomainError) -> SavingsGoal {
        let name = String(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SavingsGoal.maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .missingName }
        guard draft.target.amount > 0 else { throw .invalidAmount }
        let goal: SavingsGoal
        if let id = draft.id {
            guard let existing = try await goals.fetchSavingsGoals().first(where: { $0.id == id }) else { throw .notFound(id) }
            goal = SavingsGoal(
                id: id,
                name: name,
                target: Money(draft.target.amount, existing.target.currency),
                saved: existing.saved,
                targetMonth: draft.targetMonth,
                icon: draft.icon,
                color: draft.color,
            )
        } else {
            let currencies = try await settings.load()?.currencies ?? .initial
            try Transaction.checkCurrency(draft.target.currency, currencies: currencies)
            goal = SavingsGoal(
                id: makeID(),
                name: name,
                target: draft.target,
                saved: 0,
                targetMonth: draft.targetMonth,
                icon: draft.icon,
                color: draft.color,
            )
        }
        try await goals.save(goal)
        return goal
    }
}

/// "Add money" and "Withdraw". Only the goal changes: no movement is recorded and no account
/// balance moves, since the money never left the account it is in.
public protocol MoveSavingsGoalMoneyUseCase: Sendable {
    /// Adds a positive amount to what is set aside.
    @discardableResult
    func addMoney(id: UUID, amount: Decimal) async throws(DomainError) -> SavingsGoal
    /// Takes out a positive amount no larger than what is set aside.
    @discardableResult
    func withdraw(id: UUID, amount: Decimal) async throws(DomainError) -> SavingsGoal
}

public struct DefaultMoveSavingsGoalMoneyUseCase: MoveSavingsGoalMoneyUseCase {
    private let goals: any SavingsGoalRepository

    public init(goals: any SavingsGoalRepository) {
        self.goals = goals
    }

    public func addMoney(id: UUID, amount: Decimal) async throws(DomainError) -> SavingsGoal {
        let goal = try await find(id).adding(amount)
        try await goals.save(goal)
        return goal
    }

    public func withdraw(id: UUID, amount: Decimal) async throws(DomainError) -> SavingsGoal {
        let goal = try await find(id).withdrawing(amount)
        try await goals.save(goal)
        return goal
    }

    private func find(_ id: UUID) async throws(DomainError) -> SavingsGoal {
        guard let goal = try await goals.fetchSavingsGoals().first(where: { $0.id == id }) else { throw .notFound(id) }
        return goal
    }
}

/// Deletes a goal, leaving a tombstone like every other record so the deletion reaches other
/// devices. Nothing else changes: the money set aside was only ever tracked here.
public protocol DeleteSavingsGoalUseCase: Sendable {
    func execute(id: UUID) async throws(DomainError)
}

public struct DefaultDeleteSavingsGoalUseCase: DeleteSavingsGoalUseCase {
    private let goals: any SavingsGoalRepository

    public init(goals: any SavingsGoalRepository) {
        self.goals = goals
    }

    public func execute(id: UUID) async throws(DomainError) {
        try await goals.deleteSavingsGoal(id: id)
    }
}
