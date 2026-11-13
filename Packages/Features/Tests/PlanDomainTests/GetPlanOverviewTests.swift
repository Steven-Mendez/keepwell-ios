import Domain
import DomainSamples
import Foundation
import Testing
@testable import PlanDomain

@Suite("Plan overview")
struct GetPlanOverviewTests {
    private let now = SampleData.defaultReferenceDate
    private let sample = SampleData.standard

    private struct Recurring: PlanRecurringSource {
        let rules: [RecurringRule]
        func load() async throws(DomainError) -> (rules: [RecurringRule], subscriptionsPerMonth: Money) {
            (rules, Money(15.99, "USD"))
        }
    }

    private struct Goals: PlanGoalsSource {
        let goals: [SavingsGoalProgress]
        func load() async throws(DomainError) -> [SavingsGoalProgress] {
            goals
        }
    }

    private struct Debts: PlanDebtsSource {
        let loans: [LoanProgress]
        let debts: [PersonalDebt]
        func load() async throws(DomainError) -> (loans: [LoanProgress], debts: [PersonalDebt], totals: DebtTotals) {
            (loans, debts, DebtTotals(loans: loans.map(\.loan), debts: debts))
        }
    }

    private func useCase(empty: Bool = false) throws -> DefaultGetPlanOverviewUseCase {
        let month = try #require(YearMonth(year: 2026, month: 11))
        let calendar = Calendar.current
        return DefaultGetPlanOverviewUseCase(
            recurring: Recurring(rules: empty ? [] : sample.recurringRules),
            goals: Goals(goals: empty ? [] : SavingsGoalProgress.ordered(sample.savingsGoals, currentMonth: month)),
            debts: Debts(
                loans: empty ? [] : LoanProgress.ordered(sample.loans, today: now, calendar: calendar),
                debts: empty ? [] : sample.personalDebts,
            ),
            calendar: calendar,
            now: { [now] in now },
        )
    }

    @Test
    func summarizesTheThreeSources() async throws {
        let overview = try await useCase().execute()
        #expect(overview.recurring.hasRules)
        #expect(overview.recurring.subscriptionsPerMonth == Money(15.99, "USD"))
        let next = try #require(overview.recurring.next)
        #expect(next.date >= Calendar.current.startOfDay(for: now))
        let month = try #require(YearMonth(year: 2026, month: 11))
        let first = SavingsGoalProgress.ordered(sample.savingsGoals, currentMonth: month).first
        #expect(overview.goals.top?.goal.id == first?.goal.id)
        #expect(overview.goals.count == sample.savingsGoals.count)
        #expect(overview.debts.hasDebts)
        #expect(overview.debts.nextLoan?.next != nil)
    }

    @Test
    func countsWhatEachTotalAddsUp() async throws {
        let overview = try await useCase().execute()
        let subscriptions = sample.recurringRules.count {
            $0.isSubscription && $0.kind == .expense && RecurringSchedule.isActive($0, calendar: .current)
        }
        #expect(overview.recurring.subscriptionCount == subscriptions)
        // The open motorbike loan and the tickets owed to Ana; Juan owes, Carlos already paid.
        #expect(overview.debts.youOweCount == 2)
        #expect(overview.debts.peopleOwingCount == 1)
    }

    @Test
    func nothingPlannedYieldsEmptySummaries() async throws {
        let overview = try await useCase(empty: true).execute()
        #expect(!overview.recurring.hasRules)
        #expect(overview.recurring.next == nil)
        #expect(overview.goals.top == nil)
        #expect(!overview.debts.hasDebts)
        #expect(overview.debts.nextLoan == nil)
        #expect(overview.recurring.subscriptionCount == 0)
        #expect(overview.debts.youOweCount == 0)
        #expect(overview.debts.peopleOwingCount == 0)
    }
}
