import Domain
import DomainSamples
import Foundation
import GoalsDomain
import Testing
@testable import GoalsPresentation

@Suite("Goals view models")
@MainActor
struct GoalsViewModelTests {
    private typealias IDs = SampleData.IDs

    private func loaded(_ store: InMemoryStore = InMemoryStore(sample: .standard)) async -> GoalsViewModel {
        let viewModel = GoalsPreview.listViewModel(store: store)
        await viewModel.load()
        return viewModel
    }

    private func progress(_ viewModel: GoalsViewModel, _ id: UUID) throws -> SavingsGoalProgress {
        try #require(viewModel.overview?.progress(of: id))
    }

    @Test
    func rowsReadAmountsAndTheNextStep() async throws {
        let viewModel = await loaded()
        let trip = try progress(viewModel, IDs.tripGoal)
        #expect(viewModel.amounts(trip, hidden: false) == "C$4,500.00 of C$15,000.00")
        #expect(viewModel.amounts(trip, hidden: true) == "•••• of ••••")
        #expect(viewModel.hint(trip, hidden: false) == "Set aside C$3,500.00 a month until December 2026")
        #expect(viewModel.hint(trip, hidden: true) == "Set aside •••• a month until December 2026")
        #expect(viewModel.barFraction(trip) == 0.3)
        let fund = try progress(viewModel, IDs.emergencyGoal)
        #expect(viewModel.hint(fund, hidden: false) == "$1,800.00 to go")
        let phone = try progress(viewModel, IDs.phoneGoal)
        #expect(viewModel.hint(phone, hidden: false) == "Goal reached")
        #expect(viewModel.barFraction(phone) == 1)
    }

    @Test
    func theLastMonthAndAPassedDateReadDifferently() async throws {
        let calendar = Calendar.current
        let october = YearMonth(containing: SampleData.defaultReferenceDate, calendar: calendar)
        let store = InMemoryStore(sample: .standard)
        try await store.save(SavingsGoal(
            name: "Now", target: Money(100, "USD"), saved: 40, targetMonth: TargetMonth(october),
        ))
        try await store.save(SavingsGoal(
            name: "Late", target: Money(100, "USD"), saved: 40, targetMonth: TargetMonth(october.adding(months: -1)),
        ))
        let viewModel = await loaded(store)
        let rows = viewModel.goals
        #expect(rows.map(\.goal.name).prefix(2) == ["Late", "Now"])
        #expect(viewModel.hint(rows[0], hidden: false) == "The date passed with $60.00 to go")
        #expect(viewModel.hint(rows[1], hidden: false) == "Set aside $60.00 this month")
    }

    @Test
    func emptyWithoutGoals() async throws {
        let store = InMemoryStore(sample: .standard)
        for goal in SampleData.standard.savingsGoals {
            try await store.deleteSavingsGoal(id: goal.id)
        }
        let viewModel = await loaded(store)
        #expect(viewModel.isEmpty)
    }

    @Test
    func aNewGoalOffersBothCurrenciesAndSavesInTheChosenOne() async throws {
        let store = InMemoryStore(sample: .standard)
        let viewModel = await loaded(store)
        viewModel.newGoal()
        let editor = try #require(viewModel.editor)
        #expect(editor.isCreating)
        #expect(editor.currencyOptions == ["USD", "NIO"])
        #expect(editor.showsCurrencyPicker)
        #expect(!editor.canSave)
        editor.setName("Viaje")
        editor.targetText = "15,000"
        editor.currency = "NIO"
        editor.hasTargetMonth = true
        editor.month = 12
        editor.year = 2026
        #expect(editor.targetMonthTitle == "December 2026")
        let saved = try #require(await editor.save())
        #expect(saved.target == Money(15000, "NIO"))
        #expect(saved.saved == 0)
        #expect(try saved.targetMonth == TargetMonth(month: 12, year: 2026))
        await viewModel.sheetFinished()
        #expect(viewModel.editor == nil)
        #expect(viewModel.goals.contains { $0.goal.id == saved.id })
    }

    @Test
    func theEditorExplainsWhatItCantSave() async throws {
        let viewModel = await loaded()
        viewModel.newGoal()
        let editor = try #require(viewModel.editor)
        editor.setName("Trip")
        editor.targetText = "0"
        // A zero target leaves Save disabled instead of failing after the tap.
        #expect(!editor.canSave)
        #expect(await editor.save() == nil)
        editor.setName(String(repeating: "x", count: 80))
        #expect(editor.name.count == SavingsGoal.maxNameLength)
        #expect(editor.targetMonthTitle == "No date")
    }

    @Test
    func editingLocksTheCurrencyAndCanDelete() async throws {
        let store = InMemoryStore(sample: .standard)
        let viewModel = await loaded(store)
        viewModel.edit(IDs.tripGoal)
        let editor = try #require(viewModel.editor)
        #expect(!editor.isCreating)
        #expect(!editor.showsCurrencyPicker)
        #expect(editor.name == "Trip")
        #expect(editor.targetText == "15,000.00")
        #expect(editor.hasTargetMonth)
        #expect(editor.canDelete)
        #expect(await editor.delete())
        #expect(await !store.fetchSavingsGoals().contains { $0.id == IDs.tripGoal })
    }

    @Test
    func withdrawingCantPassWhatIsSetAside() async throws {
        let store = InMemoryStore(sample: .standard)
        let viewModel = await loaded(store)
        viewModel.withdraw(from: IDs.emergencyGoal)
        let sheet = try #require(viewModel.amountSheet)
        #expect(sheet.title == "Withdraw")
        sheet.amountText = "1200.01"
        #expect(!sheet.canSave)
        #expect(sheet.errorMessage == "You can't withdraw more than you've set aside.")
        sheet.amountText = "200"
        #expect(sheet.errorMessage == nil)
        #expect(await sheet.save())
        #expect(await store.fetchSavingsGoals().first { $0.id == IDs.emergencyGoal }?.saved == 1000)

        viewModel.addMoney(to: IDs.emergencyGoal)
        let add = try #require(viewModel.amountSheet)
        #expect(add.title == "Add money")
        add.amountText = "0"
        #expect(!add.canSave)
        add.amountText = "50.25"
        #expect(await add.save())
        await viewModel.sheetFinished()
        #expect(viewModel.overview?.progress(of: IDs.emergencyGoal)?.goal.saved == Decimal(string: "1050.25"))
    }
}
