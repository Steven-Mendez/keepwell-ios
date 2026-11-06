import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreditCardDomain

@Suite("Credit card")
struct CreditCardTests {
    private let sample = SampleData.standard

    private func detail(_ store: InMemoryStore, accountID: UUID = SampleData.IDs.mastercard) async throws -> CreditCardDetail {
        try await DefaultGetCreditCardDetailUseCase(
            accounts: store, cards: store, transactions: store, categories: store, settings: store,
            now: { SampleData.defaultReferenceDate },
        ).execute(accountID: accountID)
    }

    @Test
    func detailCollectsTheCardAndItsDebt() async throws {
        let result = try await detail(InMemoryStore(sample: sample))
        #expect(result.holder?.id == SampleData.IDs.mastercardHolder)
        #expect(result.balances.count == 2)
        #expect(result.totalDebt.currency == "USD")
        #expect(try result.totalDebt == NetWorth.total(of: result.balances, settings: sample.settings.currencies))
        #expect(result.available == nil)
    }

    @Test
    func cycleMovementsBelongToTheCardAndTheCycle() async throws {
        let result = try await detail(InMemoryStore(sample: sample))
        let cycle = try #require(result.cycle)
        #expect(result.cycleTransactions.allSatisfy { $0.accountID == SampleData.IDs.mastercard })
        #expect(result.cycleTransactions.allSatisfy { $0.date >= cycle.start && $0.date < cycle.end })
    }

    @Test
    func aDepositAccountIsNotACreditCard() async throws {
        await #expect(throws: DomainError.notFound(SampleData.IDs.savings)) {
            _ = try await detail(InMemoryStore(sample: sample), accountID: SampleData.IDs.savings)
        }
    }

    @Test
    func termsSetTheLimitAndAvailableCredit() async throws {
        let store = InMemoryStore(sample: sample)
        try await DefaultUpdateCreditTermsUseCase(accounts: store)
            .execute(accountID: SampleData.IDs.mastercard, limit: Money(1000, "USD"), cutoffDay: 20, dueDay: 5)
        let result = try await detail(store)
        #expect(result.account.creditTerms?.cutoffDay == 20)
        #expect(result.account.creditTerms?.debtMode == .dual)
        let available = try #require(result.available)
        #expect(available.amount == 1000 + result.totalDebt.amount)
        #expect(result.nextCutoff != nil)
    }
}
