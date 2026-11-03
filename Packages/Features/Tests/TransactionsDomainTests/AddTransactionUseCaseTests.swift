import Domain
import Foundation
import Testing
@testable import TransactionsDomain

@Suite("AddTransactionUseCase")
struct AddTransactionUseCaseTests {
    private let repository = MockTransactionRepository()
    private var sut: DefaultAddTransactionUseCase {
        DefaultAddTransactionUseCase(repository: repository)
    }

    @Test(arguments: ["-0.01", "-100", "0"])
    func rejectsNonPositiveAmounts(amount: String) async {
        await #expect(throws: DomainError.invalidAmount) {
            try await sut.execute(Fixture.transaction(amount, .expense))
        }
        #expect(await repository.added.isEmpty)
    }

    @Test(arguments: ["", "US", "XYZ", "dollars"])
    func rejectsUnknownCurrencies(code: String) async {
        await #expect(throws: DomainError.invalidCurrency(code)) {
            try await sut.execute(Fixture.transaction("10", .expense, currency: code))
        }
        #expect(await repository.added.isEmpty)
    }

    @Test
    func rejectsTransfers() async {
        await #expect(throws: DomainError.unsupportedTransactionKind(.transfer)) {
            try await sut.execute(Fixture.transaction("10", .transfer))
        }
    }

    @Test
    func rejectsCategoryOfAnotherKind() async {
        let draft = Transaction(
            amount: 10,
            currency: "USD",
            kind: .expense,
            category: Fixture.salary,
            date: Fixture.date(2026, 3, 15),
        )

        await #expect(throws: DomainError.categoryKindMismatch(expected: .expense, actual: .income)) {
            try await sut.execute(draft)
        }
    }

    @Test
    func savesExactAmount() async throws {
        let draft = Fixture.transaction("1234.56", .expense)

        let saved = try await sut.execute(draft)

        #expect(saved.amount == Fixture.decimal("1234.56"))
        #expect(await repository.added == [saved])
    }

    @Test
    func acceptsSmallestPositiveAmount() async throws {
        let saved = try await sut.execute(Fixture.transaction("0.01", .income))
        #expect(saved.amount == Fixture.decimal("0.01"))
    }

    @Test
    func normalizesCurrencyCode() async throws {
        let saved = try await sut.execute(Fixture.transaction("10", .expense, currency: " nio "))
        #expect(saved.currency == "NIO")
    }

    @Test(arguments: [("  Almuerzo  ", "Almuerzo"), ("   ", nil), (nil, nil)] as [(String?, String?)])
    func normalizesNote(input: String?, expected: String?) async throws {
        let saved = try await sut.execute(Fixture.transaction("10", .expense, note: input))
        #expect(saved.note == expected)
    }

    @Test
    func propagatesRepositoryErrors() async {
        let failing = DefaultAddTransactionUseCase(repository: MockTransactionRepository(error: .persistence("locked")))

        await #expect(throws: DomainError.persistence("locked")) {
            try await failing.execute(Fixture.transaction("10", .expense))
        }
    }
}
