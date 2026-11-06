import Foundation
@testable import Domain

/// Builders with generic values so each test states only what it is about.
enum Fixtures {
    static let usdNio: ExchangeRate = {
        guard let rate = try? ExchangeRate(principal: "USD", second: "NIO", rate: decimal("36.6243")) else {
            preconditionFailure("valid rate")
        }
        return rate
    }()

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Managua") ?? .gmt
        return calendar
    }()

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string) ?? .nan
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    static func transaction(
        _ kind: TransactionKind = .expense,
        amount: String,
        currency: String = "USD",
        account: UUID = UUID(),
        card: UUID? = nil,
        destination: UUID? = nil,
        actualDebited: String? = nil,
        category: String? = "other-expense",
        status: TransactionStatus = .confirmed,
        date: Date = Self.date(2026, 10, 5),
        rate: ExchangeRate = Self.usdNio,
    ) -> Transaction {
        Transaction(
            date: date,
            status: status,
            description: "Movimiento",
            kind: kind,
            categoryID: kind == .transfer ? nil : category,
            amount: decimal(amount),
            currency: currency,
            accountID: account,
            cardID: card,
            destinationAccountID: destination,
            actualDebitedPrincipal: actualDebited.map(decimal),
            exchangeRate: rate,
        )
    }
}
