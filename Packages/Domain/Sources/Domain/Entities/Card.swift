import Foundation

public enum CardKind: String, Codable, CaseIterable, Sendable {
    case debit
    case creditHolder
    /// A bank transfer method linked to a deposit account ("Transferencias Banco").
    case transfer
}

public enum CardNetwork: String, Codable, CaseIterable, Sendable {
    case visa
    case mastercard
    case amex
    case other
}

/// Card art palette, by name so the domain stays free of UI colors. Raw values are stored, so a
/// color no longer offered (`violeta`, `coral`, `lima`) stays here for the cards saved with it.
public enum CardColor: String, Codable, CaseIterable, Sendable {
    case azul
    case grafito
    case platino
    case verde
    case violeta
    case coral
    case rojo
    case oro
    case lima
}

/// The "valid thru" printed on a plastic: only month and year, as the card shows it. A card works
/// through the last day of that month.
public struct CardExpiry: Hashable, Sendable, Codable, Comparable {
    public let month: Int
    public let year: Int

    public init(month: Int, year: Int) throws(DomainError) {
        guard (1 ... 12).contains(month), (2000 ... 2199).contains(year) else { throw .invalidExpiry }
        self.month = month
        self.year = year
    }

    /// The first day of the expiry month: a month before the card stops working, early enough to
    /// update the services charged to it.
    public func reminderDay(calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// A payment method: a plastic or a transfer channel, always linked to one account.
public struct Card: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let accountID: UUID
    public let kind: CardKind
    public let network: CardNetwork?
    public let lastFour: String?
    public let color: CardColor?
    /// The bank's name for the plastic ("Premia", "Platinum Walmart"), which tells apart two cards
    /// of the same bank and network better than their digits.
    public let productName: String?
    public let expiry: CardExpiry?

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        kind: CardKind,
        network: CardNetwork? = nil,
        lastFour: String? = nil,
        color: CardColor? = nil,
        productName: String? = nil,
        expiry: CardExpiry? = nil,
    ) throws(DomainError) {
        if let lastFour {
            guard lastFour.count == 4, lastFour.allSatisfy(\.isASCIIDigit) else { throw .invalidLastFour(lastFour) }
        }
        self.id = id
        self.accountID = accountID
        self.kind = kind
        self.network = network
        self.lastFour = lastFour
        self.color = color
        let trimmed = productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.productName = trimmed?.isEmpty == false ? trimmed : nil
        self.expiry = expiry
    }
}

extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
