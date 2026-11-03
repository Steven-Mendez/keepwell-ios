import Domain
import DomainSamples
import Foundation
import Testing
@testable import AccountsDomain

@Suite("Accounts overview")
struct AccountsOverviewTests {
    private let sample = SampleData.standard

    private func overview() async throws -> AccountsOverview {
        let store = InMemoryStore(sample: sample)
        return try await DefaultGetAccountsOverviewUseCase(
            accounts: store, cards: store, transactions: store, settings: store,
        ).execute()
    }

    @Test
    func groupsAccountsByKind() async throws {
        let result = try await overview()
        #expect(result.creditCards.count == 2)
        #expect(result.deposits.count == 2)
        #expect(result.cash.count == 1)
    }

    @Test
    func dualCreditCardShowsSecondCurrencyDebtFirst() async throws {
        let card = try #require(try await overview().creditCards.first { $0.account.id == SampleData.IDs.mastercard })
        #expect(card.balances.map(\.currency) == ["NIO", "USD"])
        #expect(card.balances.allSatisfy { $0.amount < 0 })
        #expect(card.plasticCount == 2)
        #expect(card.holder?.lastFour == "4321")
    }

    @Test
    func depositShowsItsDebitCardsWithoutTheTransferChannel() async throws {
        let deposit = try #require(try await overview().deposits.first { $0.account.id == SampleData.IDs.savings })
        #expect(deposit.debitCards.map(\.kind) == [.debit])
        #expect(deposit.debitCards.allSatisfy { $0.accountID == SampleData.IDs.savings })
    }

    @Test
    func depositWithOnlyATransferChannelHasNoCards() throws {
        let account = Account(name: "Savings", bank: "Bank", kind: .deposit, openingBalances: [Money(10, "USD")], openingDate: .now)
        let result = try DefaultGetAccountsOverviewUseCase.overview(
            accounts: [account],
            cards: [Card(accountID: account.id, kind: .transfer)],
            transactions: [],
            currencies: sample.settings.currencies,
            calendar: .current,
        )
        #expect(result.deposits.first?.debitCards.isEmpty == true)
    }

    @Test
    func cashIncludesTheWithdrawalAndItsPrincipalEquivalent() async throws {
        let cash = try #require(try await overview().cash.first)
        // 7,500 opening + 1,200 withdrawal − 250 lunch − 60 bus.
        #expect(cash.balance == Money(8390, "NIO"))
        #expect(cash.principalEquivalent?.currency == "USD")
    }

    @Test
    func netWorthSumsEverythingInPrincipal() async throws {
        let result = try await overview()
        let balances = sample.accounts.flatMap { Balances.balance(of: $0, transactions: sample.transactions, calendar: .current) }
        #expect(try result.netWorth == (NetWorth.total(of: balances, settings: sample.settings.currencies)))
    }
}
