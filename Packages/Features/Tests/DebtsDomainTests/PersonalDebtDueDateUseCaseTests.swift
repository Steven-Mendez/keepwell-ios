import Domain
import DomainSamples
import Foundation
import Testing
@testable import DebtsDomain

/// Saving a personal debt's due date (keepwell-web `savePersonalDebt`): kept as the start of the
/// day, removed when an edit leaves it out, and never before the debt.
@Suite("Personal debt due date use case")
struct PersonalDebtDueDateUseCaseTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Managua") ?? .gmt
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func draft(id: UUID? = nil, due: Date? = nil) -> PersonalDebtDraft {
        PersonalDebtDraft(id: id, person: "Ana", direction: .theyOweMe, amount: Money(12, "USD"), date: date(2026, 9, 1), dueDate: due)
    }

    @Test
    func savesItAsTheStartOfTheDayRemovesItWhenLeftOutAndRejectsOneBeforeTheDebt() async throws {
        let store = InMemoryStore(sample: SampleData.standard)
        let save = DefaultSavePersonalDebtUseCase(debts: store, settings: store, calendar: calendar)
        let saved = try await save.execute(draft(due: date(2026, 11, 15, hour: 17)))
        #expect(saved.dueDate == date(2026, 11, 15, hour: 0))

        let sameDay = try await save.execute(draft(id: saved.id, due: date(2026, 9, 1, hour: 8)))
        #expect(sameDay.dueDate == date(2026, 9, 1, hour: 0))

        let removed = try await save.execute(draft(id: saved.id))
        #expect(removed.dueDate == nil)
        #expect(try await store.fetchPersonalDebts().first { $0.id == saved.id }?.dueDate == nil)

        await #expect(throws: DomainError.invalidDueDate) {
            try await save.execute(draft(due: date(2026, 8, 31)))
        }
    }

    @Test
    func repaymentsKeepIt() async throws {
        let store = InMemoryStore(sample: SampleData.standard)
        let saved = try await DefaultSavePersonalDebtUseCase(debts: store, settings: store, calendar: calendar)
            .execute(draft(due: date(2026, 11, 15)))
        let repaid = try await DefaultUpdatePersonalDebtUseCase(debts: store).repay(id: saved.id, amount: 5, on: date(2026, 11, 2))
        #expect(repaid.dueDate == saved.dueDate)
    }
}
