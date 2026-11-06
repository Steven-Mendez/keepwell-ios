import Foundation
import Testing
@testable import Domain

@Suite("Savings goals")
struct SavingsGoalsTests {
    private let november = YearMonth(year: 2026, month: 11) ?? YearMonth(containing: .now, calendar: .current)

    private func goal(
        _ name: String = "Trip",
        target: String = "15000",
        saved: String = "0",
        month: Int? = nil,
        year: Int = 2026,
    ) throws -> SavingsGoal {
        try SavingsGoal(
            name: name,
            target: Money(Decimal(string: target) ?? 0, "NIO"),
            saved: Decimal(string: saved) ?? 0,
            targetMonth: month.map { month throws(DomainError) in try TargetMonth(month: month, year: year) },
        )
    }

    @Test
    func twoMonthsSplitWhatIsMissingInHalves() throws {
        let progress = try SavingsGoalProgress(goal: goal(month: 12), currentMonth: november)
        #expect(progress.monthsLeft == 2)
        #expect(progress.monthlyAmount == 7500)
        #expect(progress.remaining == 15000)
        #expect(progress.fraction == 0)
        #expect(!progress.isReached)
        #expect(!progress.isOverdue)
    }

    @Test
    func theMonthlyAmountRoundsUpToTheCent() throws {
        let progress = try SavingsGoalProgress(goal: goal(target: "100", month: 1, year: 2027), currentMonth: november)
        #expect(progress.monthsLeft == 3)
        #expect(progress.monthlyAmount == Decimal(string: "33.34"))
    }

    @Test
    func theSameMonthAsksForEverythingLeft() throws {
        let progress = try SavingsGoalProgress(goal: goal(saved: "2500.5", month: 11), currentMonth: november)
        #expect(progress.monthsLeft == 1)
        #expect(progress.monthlyAmount == Decimal(string: "12499.5"))
    }

    @Test
    func aPassedMonthBeforeReachingIsOverdue() throws {
        let progress = try SavingsGoalProgress(goal: goal(saved: "1000", month: 10), currentMonth: november)
        #expect(progress.isOverdue)
        #expect(progress.monthsLeft == nil)
        #expect(progress.monthlyAmount == nil)
        #expect(progress.remaining == 14000)
    }

    @Test
    func aReachedGoalAsksForNothingAndCanOvershoot() throws {
        let reached = try SavingsGoalProgress(goal: goal(target: "800", saved: "1000", month: 12), currentMonth: november)
        #expect(reached.isReached)
        #expect(reached.remaining == 0)
        #expect(reached.fraction == Decimal(string: "1.25"))
        #expect(reached.monthlyAmount == nil)
        #expect(!reached.isOverdue)
        let late = try SavingsGoalProgress(goal: goal(target: "800", saved: "800", month: 1), currentMonth: november)
        #expect(late.isReached)
        #expect(!late.isOverdue)
    }

    @Test
    func withoutADateThereIsNoMonthlyFigure() throws {
        let progress = try SavingsGoalProgress(goal: goal(saved: "3750"), currentMonth: november)
        #expect(progress.monthsLeft == nil)
        #expect(progress.monthlyAmount == nil)
        #expect(!progress.isOverdue)
        #expect(progress.fraction == Decimal(string: "0.25"))
    }

    @Test
    func openGoalsBySoonestMonthThenUndatedThenReached() throws {
        let goals = try [
            goal("Car", target: "10", saved: "10", month: 12),
            goal("bike"),
            goal("Trip", month: 3, year: 2027),
            goal("Laptop", month: 12),
            goal("Apartment"),
            goal("Late", month: 9),
            goal("Phone", target: "10", saved: "20"),
        ]
        let ordered = SavingsGoalProgress.ordered(goals, currentMonth: november).map(\.goal.name)
        #expect(ordered == ["Late", "Laptop", "Trip", "Apartment", "bike", "Car", "Phone"])
    }

    @Test
    func targetMonthsStayInRange() {
        #expect(throws: DomainError.invalidTargetMonth) { try TargetMonth(month: 13, year: 2026) }
        #expect(throws: DomainError.invalidTargetMonth) { try TargetMonth(month: 0, year: 2026) }
        #expect(throws: DomainError.invalidTargetMonth) { try TargetMonth(month: 1, year: 1999) }
        #expect(throws: DomainError.invalidTargetMonth) { try TargetMonth(month: 1, year: 2200) }
        #expect((try? TargetMonth(month: 12, year: 2199)) != nil)
    }

    @Test
    func addingAndWithdrawingKeepWhatIsSetAsideValid() throws {
        let trip = try goal(saved: "100")
        #expect(try trip.adding(Decimal(string: "50.25") ?? 0).saved == Decimal(string: "150.25"))
        #expect(try trip.withdrawing(100).saved == 0)
        #expect(throws: DomainError.invalidAmount) { try trip.adding(0) }
        #expect(throws: DomainError.invalidAmount) { try trip.withdrawing(-1) }
        #expect(throws: DomainError.invalidAmount) { try trip.withdrawing(Decimal(string: "100.01") ?? 0) }
    }
}
