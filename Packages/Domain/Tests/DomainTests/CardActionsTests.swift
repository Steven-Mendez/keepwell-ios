import DomainSamples
import Foundation
import Testing
@testable import Domain

@Suite("Card actions")
struct CardActionsTests {
    private typealias IDs = SampleData.IDs

    @Test
    func repaintingKeepsEverythingElse() async throws {
        let store = InMemoryStore(sample: .standard)
        let before = try await card(IDs.savingsDebit, in: store)
        try await DefaultSetCardColorUseCase(cards: store).execute(cardID: IDs.savingsDebit, color: .rojo)
        let after = try await card(IDs.savingsDebit, in: store)
        #expect(after.color == .rojo)
        #expect(after.lastFour == before.lastFour)
        #expect(after.network == before.network)
        #expect(after.accountID == before.accountID)
    }

    @Test
    func aTransferChannelHasNoArtToRepaint() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.notFound(IDs.savingsTransfer)) {
            try await DefaultSetCardColorUseCase(cards: store).execute(cardID: IDs.savingsTransfer, color: .verde)
        }
    }

    @Test
    func cardDetailsAreSavedAndKeepTheArt() async throws {
        let store = InMemoryStore(sample: .standard)
        let expiry = try CardExpiry(month: 9, year: 2028)
        try await DefaultSetCardDetailsUseCase(cards: store).execute(cardID: IDs.visaHolder, productName: "  Premia ", expiry: expiry)
        let after = try await card(IDs.visaHolder, in: store)
        #expect(after.productName == "Premia")
        #expect(after.expiry == expiry)
        #expect(after.color == .grafito)
        #expect(after.lastFour == "9012")

        try await DefaultSetCardDetailsUseCase(cards: store).execute(cardID: IDs.visaHolder, productName: " ", expiry: nil)
        let cleared = try await card(IDs.visaHolder, in: store)
        #expect(cleared.productName == nil)
        #expect(cleared.expiry == nil)
    }

    @Test
    func aTransferChannelHasNoDetails() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.notFound(IDs.savingsTransfer)) {
            try await DefaultSetCardDetailsUseCase(cards: store).execute(cardID: IDs.savingsTransfer, productName: "X", expiry: nil)
        }
    }

    @Test(arguments: [(0, 2028), (13, 2028), (5, 28)])
    func expiryNeedsARealMonthAndFullYear(month: Int, year: Int) {
        #expect(throws: DomainError.invalidExpiry) { try CardExpiry(month: month, year: year) }
    }

    @Test
    func expiryRemindsOnTheFirstOfItsMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Managua"))
        let day = try #require(CardExpiry(month: 5, year: 2029).reminderDay(calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day], from: day) == DateComponents(year: 2029, month: 5, day: 1))
        #expect(try CardExpiry(month: 2, year: 2028) < CardExpiry(month: 9, year: 2028))
    }

    @Test
    func cardNumberIsSavedAndKeepsTheArt() async throws {
        let store = InMemoryStore(sample: .standard)
        try await DefaultSetCardNumberUseCase(cards: store).execute(cardID: IDs.visaHolder, lastFour: "4321", network: .mastercard)
        let after = try await card(IDs.visaHolder, in: store)
        #expect(after.lastFour == "4321")
        #expect(after.network == .mastercard)
        #expect(after.color == .grafito)
    }

    @Test
    func aCreditCardCannotLoseItsDigits() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.invalidLastFour("")) {
            try await DefaultSetCardNumberUseCase(cards: store).execute(cardID: IDs.visaHolder, lastFour: nil, network: .visa)
        }
    }

    @Test
    func aDebitCardMayClearItsDigits() async throws {
        let store = InMemoryStore(sample: .standard)
        try await DefaultSetCardNumberUseCase(cards: store).execute(cardID: IDs.savingsDebit, lastFour: "", network: nil)
        let after = try await card(IDs.savingsDebit, in: store)
        #expect(after.lastFour == nil)
        #expect(after.network == nil)
    }

    @Test
    func digitsMustBeFour() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.invalidLastFour("12")) {
            try await DefaultSetCardNumberUseCase(cards: store).execute(cardID: IDs.visaHolder, lastFour: "12", network: nil)
        }
    }

    @Test
    func aTransferChannelHasNoNumber() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.notFound(IDs.savingsTransfer)) {
            try await DefaultSetCardNumberUseCase(cards: store).execute(cardID: IDs.savingsTransfer, lastFour: "1234", network: nil)
        }
    }

    @Test
    func renamingTrimsTheName() async throws {
        let store = InMemoryStore(sample: .standard)
        try await DefaultRenameAccountUseCase(accounts: store).execute(accountID: IDs.savings, name: "  Travel  ")
        let account = try #require(await store.fetchAccounts().first { $0.id == IDs.savings })
        #expect(account.name == "Travel")
        #expect(account.bank == "Bank One")
    }

    @Test
    func anEmptyNameIsRefused() async {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.missingName) {
            try await DefaultRenameAccountUseCase(accounts: store).execute(accountID: IDs.savings, name: "   ")
        }
    }

    private func card(_ id: UUID, in store: InMemoryStore) async throws -> Card {
        try #require(await store.fetchCards().first { $0.id == id })
    }
}
