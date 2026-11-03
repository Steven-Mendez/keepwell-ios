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
    func detailCollectsHolderAdditionalsAndDebt() async throws {
        let result = try await detail(InMemoryStore(sample: sample))
        #expect(result.holder?.id == SampleData.IDs.mastercardHolder)
        #expect(result.additionals.map(\.id) == [SampleData.IDs.mastercardAdditional])
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

    @Test
    func newAdditionalReusesTheHoldersNetwork() async throws {
        let store = InMemoryStore(sample: sample)
        let card = try await DefaultAddAdditionalCardUseCase(cards: store).execute(NewAdditionalCard(
            accountID: SampleData.IDs.mastercard, holderName: " Grandma ", lastFour: "1111", color: .coral, cycleCap: Money(1500, "NIO"),
        ))
        let holder = try #require(sample.cards.first { $0.id == SampleData.IDs.mastercardHolder })
        #expect(card.network == holder.network)
        #expect(card.additional?.holderName == "Grandma")
        #expect(await store.fetchCards().contains(card))
    }

    @Test
    func newAdditionalNeedsSomeoneToCarryIt() async throws {
        let store = InMemoryStore(sample: sample)
        await #expect(throws: DomainError.missingName) {
            _ = try await DefaultAddAdditionalCardUseCase(cards: store).execute(NewAdditionalCard(
                accountID: SampleData.IDs.mastercard, holderName: "  ", lastFour: nil, color: .lima, cycleCap: nil,
            ))
        }
    }

    @Test
    func freezingKeepsTheOtherControls() async throws {
        let store = InMemoryStore(sample: sample)
        let card = try #require(sample.cards.first { $0.id == SampleData.IDs.mastercardAdditional })
        let controls = try #require(card.additional)
        try await DefaultUpdateAdditionalCardUseCase(cards: store).execute(cardID: card.id, controls: controls.with(isFrozen: true))
        let saved = try #require(await store.fetchCards().first { $0.id == card.id }?.additional)
        #expect(saved.isFrozen)
        #expect(saved.cycleCap == controls.cycleCap)
        #expect(saved.allowedCategoryIDs == controls.allowedCategoryIDs)
    }

    @Test
    func aTwoCurrencyCardCapsItsAdditionalsInTheLocalCurrency() async throws {
        let result = try await detail(InMemoryStore(sample: sample))
        #expect(result.account.currencies.count == 2)
        #expect(result.capCurrency == "NIO")
        let single = try await detail(InMemoryStore(sample: sample), accountID: SampleData.IDs.visa)
        #expect(single.capCurrency == single.account.currencies.first)
    }

    @Test
    func clearingTheCapRemovesIt() {
        let controls = AdditionalCardControls(holderName: "Family", cycleCap: Money(100, "NIO"))
        #expect(controls.with(cycleCap: .some(nil)).cycleCap == nil)
        #expect(controls.with(isFrozen: true).cycleCap == Money(100, "NIO"))
    }
}
