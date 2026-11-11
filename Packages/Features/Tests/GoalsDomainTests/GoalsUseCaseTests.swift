import Domain
import DomainSamples
import Foundation
import Testing
@testable import GoalsDomain

@Suite("Savings goal use cases")
struct GoalsUseCaseTests {
    private typealias IDs = SampleData.IDs
    private let sample = SampleData.standard

    private func store() -> InMemoryStore {
        InMemoryStore(sample: sample)
    }

    @Test
    func theOverviewOrdersGoalsAndCountsFromThisMonth() async throws {
        let store = store()
        let overview = try await DefaultGetSavingsGoalsUseCase(
            goals: store, settings: store, now: { SampleData.defaultReferenceDate },
        ).execute()
        #expect(overview.goals.map(\.goal.id) == [IDs.tripGoal, IDs.emergencyGoal, IDs.phoneGoal])
        let trip = try #require(overview.progress(of: IDs.tripGoal))
        // October to December is three months for the C$10,500 still missing.
        #expect(trip.monthsLeft == 3)
        #expect(trip.monthlyAmount == 3500)
        #expect(overview.currencies == sample.settings.currencies)
    }

    @Test
    func creatingTrimsTheNameAndStartsWithNothingSetAside() async throws {
        let store = store()
        let id = UUID()
        let save = DefaultSaveSavingsGoalUseCase(goals: store, settings: store, makeID: { id })
        let month = try TargetMonth(month: 12, year: 2026)
        let goal = try await save.execute(SavingsGoalDraft(
            name: "  Viaje  ", target: Money(15000, "NIO"), targetMonth: month, icon: "airplane", color: "blue",
        ))
        #expect(goal == SavingsGoal(
            id: id, name: "Viaje", target: Money(15000, "NIO"), saved: 0, targetMonth: month, icon: "airplane", color: "blue",
        ))
        #expect(await store.fetchSavingsGoals().last == goal)
    }

    @Test
    func aLongNameIsCutAtTheLimit() async throws {
        let store = store()
        let goal = try await DefaultSaveSavingsGoalUseCase(goals: store, settings: store).execute(SavingsGoalDraft(
            name: String(repeating: "a", count: 70), target: Money(10, "USD"),
        ))
        #expect(goal.name.count == SavingsGoal.maxNameLength)
    }

    @Test
    func creatingChecksNameAmountAndCurrency() async {
        let store = store()
        let save = DefaultSaveSavingsGoalUseCase(goals: store, settings: store)
        await #expect(throws: DomainError.missingName) {
            try await save.execute(SavingsGoalDraft(name: "   ", target: Money(10, "USD")))
        }
        await #expect(throws: DomainError.invalidAmount) {
            try await save.execute(SavingsGoalDraft(name: "Trip", target: Money(0, "USD")))
        }
        await #expect(throws: DomainError.invalidAmount) {
            try await save.execute(SavingsGoalDraft(name: "Trip", target: Money(-1, "USD")))
        }
        await #expect(throws: DomainError.invalidCurrency("EUR")) {
            try await save.execute(SavingsGoalDraft(name: "Trip", target: Money(10, "EUR")))
        }
        #expect(await store.fetchSavingsGoals() == sample.savingsGoals)
    }

    @Test
    func editingKeepsWhatIsSetAsideAndTheOriginalCurrency() async throws {
        let store = store()
        let save = DefaultSaveSavingsGoalUseCase(goals: store, settings: store)
        let edited = try await save.execute(SavingsGoalDraft(
            id: IDs.tripGoal, name: "Japan", target: Money(20000, "USD"), targetMonth: nil, icon: "globe", color: "pink",
        ))
        #expect(edited.name == "Japan")
        #expect(edited.target == Money(20000, "NIO"))
        #expect(edited.saved == 4500)
        #expect(edited.targetMonth == nil)
        #expect(edited.icon == "globe")
        #expect(await store.fetchSavingsGoals().first { $0.id == IDs.tripGoal } == edited)
        await #expect(throws: DomainError.self) {
            try await save.execute(SavingsGoalDraft(id: UUID(), name: "Ghost", target: Money(1, "USD")))
        }
    }

    @Test
    func addingAndWithdrawingOnlyChangeTheGoal() async throws {
        let store = store()
        let move = DefaultMoveSavingsGoalMoneyUseCase(goals: store)
        let before = await store.fetchTransactions(in: nil)
        #expect(try await move.addMoney(id: IDs.tripGoal, amount: Decimal(string: "500.5") ?? 0).saved == Decimal(string: "5000.5"))
        #expect(try await move.withdraw(id: IDs.tripGoal, amount: Decimal(string: "0.5") ?? 0).saved == 5000)
        #expect(await store.fetchSavingsGoals().first { $0.id == IDs.tripGoal }?.saved == 5000)
        #expect(await store.fetchTransactions(in: nil) == before)

        await #expect(throws: DomainError.invalidAmount) { try await move.addMoney(id: IDs.tripGoal, amount: 0) }
        await #expect(throws: DomainError.invalidAmount) { try await move.withdraw(id: IDs.tripGoal, amount: 5001) }
        await #expect(throws: DomainError.invalidAmount) { try await move.withdraw(id: IDs.tripGoal, amount: -1) }
        #expect(await store.fetchSavingsGoals().first { $0.id == IDs.tripGoal }?.saved == 5000)
    }

    @Test
    func deletingRemovesTheGoal() async throws {
        let store = store()
        let delete = DefaultDeleteSavingsGoalUseCase(goals: store)
        try await delete.execute(id: IDs.phoneGoal)
        #expect(await !store.fetchSavingsGoals().contains { $0.id == IDs.phoneGoal })
        await #expect(throws: DomainError.notFound(IDs.phoneGoal)) { try await delete.execute(id: IDs.phoneGoal) }
    }
}
