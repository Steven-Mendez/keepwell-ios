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

/// A payment method: a plastic or a transfer channel, always linked to one account.
public struct Card: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let accountID: UUID
    public let kind: CardKind
    public let network: CardNetwork?
    public let lastFour: String?
    public let color: CardColor?
    /// A frozen card can't be chosen to pay, so nothing gets logged on a card the person locked.
    public let isFrozen: Bool

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        kind: CardKind,
        network: CardNetwork? = nil,
        lastFour: String? = nil,
        color: CardColor? = nil,
        isFrozen: Bool = false,
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
        self.isFrozen = isFrozen
    }

    /// The same card frozen or unfrozen.
    public func with(isFrozen: Bool) -> Self {
        guard let copy = try? Self(
            id: id,
            accountID: accountID,
            kind: kind,
            network: network,
            lastFour: lastFour,
            color: color,
            isFrozen: isFrozen,
        ) else { return self }
        return copy
    }
}

extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
