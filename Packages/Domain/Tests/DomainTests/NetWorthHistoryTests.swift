import Foundation
import Testing
@testable import Domain

/// The shared fixture: keepwell-web `tests/domain/net-worth-history.test.ts` builds the same ledger
/// and expects the same numbers. Today is Nov 6 2026; the rate is 36.5 NIO per USD.
@Suite("Net worth history")
struct NetWorthHistoryTests {
    private let calendar = Fixtures.calendar
    private let now = Fixtures.date(2026, 11, 6)
    private let rate = Fixtures.decimal("36.5")

    private enum IDs {
        static let bank = UUID()
        static let visa = UUID()
        static let wallet = UUID()
    }

    private var settings: CurrencySettings {
        get throws { try CurrencySettings(principal: "USD", second: "NIO", rate: rate) }
    }

    private func account(_ id: UUID, _ kind: AccountKind, _ opening: String, _ currency: String, opened: Date) throws -> Account {
        try Account(
            id: id, name: "\(kind)", kind: kind,
            openingBalances: [Money(Fixtures.decimal(opening), currency)],
            openingDate: opened,
            creditTerms: kind == .credit ? CreditTerms(debtMode: .principal) : nil,
        )
    }

    private func movement(
        _ kind: TransactionKind,
        _ amount: String,
        _ currency: String = "USD",
        on date: Date,
        from account: UUID = IDs.bank,
        to destination: UUID? = nil,
        planned: Bool = false,
    ) throws -> Transaction {
        try Fixtures.transaction(
            kind, amount: amount, currency: currency, account: account, destination: destination,
            status: planned ? .planned : .confirmed, date: date,
            rate: ExchangeRate(principal: "USD", second: "NIO", rate: rate),
        )
    }

    private func ledger() throws -> (accounts: [Account], transactions: [Transaction]) {
        let accounts = try [
            account(IDs.bank, .deposit, "1000", "USD", opened: Fixtures.date(2026, 7, 15, hour: 0)),
            account(IDs.visa, .credit, "-200", "USD", opened: Fixtures.date(2026, 9, 1, hour: 0)),
            account(IDs.wallet, .cash, "3650", "NIO", opened: Fixtures.date(2026, 10, 10, hour: 0)),
        ]
        let transactions = try [
            // Before the bank's opening day: already part of its opening balance.
            movement(.expense, "50", on: Fixtures.date(2026, 7, 10)),
            movement(.income, "500", on: Fixtures.date(2026, 7, 20)),
            movement(.expense, "300", on: Fixtures.date(2026, 8, 5)),
            movement(.expense, "120", on: Fixtures.date(2026, 9, 3), from: IDs.visa),
            // The last hour of September still belongs to September.
            movement(.expense, "80", on: Fixtures.date(2026, 9, 30, hour: 23)),
            movement(.transfer, "100", on: Fixtures.date(2026, 10, 1, hour: 0), to: IDs.visa),
            movement(.expense, "365", "NIO", on: Fixtures.date(2026, 10, 12), from: IDs.wallet),
            movement(.expense, "1000", on: Fixtures.date(2026, 10, 20), planned: true),
            movement(.expense, "100", "NIO", on: Fixtures.date(2026, 11, 2), from: IDs.wallet),
            movement(.income, "200", on: Fixtures.date(2026, 11, 3)),
            // Later today counts; later this month doesn't yet.
            movement(.expense, "10", on: Fixtures.date(2026, 11, 6, hour: 20)),
            movement(.expense, "50", on: Fixtures.date(2026, 11, 20)),
        ]
        return (accounts, transactions)
    }

    @Test
    func valuesEachMonthEndAtTodaysRate() throws {
        let (accounts, transactions) = try ledger()
        let points = try NetWorthHistory.points(
            accounts: accounts, transactions: transactions, settings: settings, now: now, calendar: calendar,
        )
        // Months before July, when the first account opened, are left out.
        #expect(points.map(\.month.description) == ["2026-07", "2026-08", "2026-09", "2026-10", "2026-11"])
        #expect(points.allSatisfy { $0.total.currency == "USD" })
        #expect(points.map { $0.total.amount.rounded(scale: 2) } == ["1500", "1200", "800", "890", "1077.26"].map(Fixtures.decimal))
        let change = try #require(NetWorthHistory.change(of: points))
        #expect(change.rounded(scale: 2) == Fixtures.decimal("-422.74"))
    }

    @Test
    func keepsTheLastTwelveMonths() throws {
        let accounts = try [account(IDs.bank, .deposit, "100", "USD", opened: Fixtures.date(2024, 3, 1, hour: 0))]
        let points = try NetWorthHistory.points(accounts: accounts, transactions: [], settings: settings, now: now, calendar: calendar)
        #expect(points.count == 12)
        #expect(points.first?.month.description == "2025-12")
        #expect(points.last?.month.description == "2026-11")
        #expect(points.allSatisfy { $0.total.amount == 100 })
        #expect(NetWorthHistory.change(of: points) == 0)
        #expect(NetWorthHistory.change(of: Array(points.prefix(1))) == nil)
    }

    @Test
    func noAccountsNoPoints() throws {
        let points = try NetWorthHistory.points(accounts: [], transactions: [], settings: settings, now: now, calendar: calendar)
        #expect(points.isEmpty)
    }
}
