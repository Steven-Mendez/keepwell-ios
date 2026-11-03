import Foundation

public enum CardKind: String, Codable, CaseIterable, Sendable {
    case debit
    case creditHolder
    case creditAdditional
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

/// Controls the holder sets on an additional card given to someone else.
public struct AdditionalCardControls: Hashable, Sendable, Codable {
    /// Who carries it ("Super family"); shown as the card's name.
    public let holderName: String
    /// Spending cap per billing cycle; `nil` means no cap.
    public let cycleCap: Money?
    /// Empty means every category is allowed.
    public let allowedCategoryIDs: [String]
    /// Pre-selected category when recording its purchases.
    public let defaultCategoryID: String?
    public let alertEachPurchase: Bool
    /// Alert when spending reaches the cap threshold set in settings (80% by default).
    public let alertNearCap: Bool
    public let isFrozen: Bool

    public init(
        holderName: String,
        cycleCap: Money? = nil,
        allowedCategoryIDs: [String] = [],
        defaultCategoryID: String? = nil,
        alertEachPurchase: Bool = true,
        alertNearCap: Bool = true,
        isFrozen: Bool = false,
    ) {
        self.holderName = holderName
        self.cycleCap = cycleCap
        self.allowedCategoryIDs = allowedCategoryIDs
        self.defaultCategoryID = defaultCategoryID
        self.alertEachPurchase = alertEachPurchase
        self.alertNearCap = alertNearCap
        self.isFrozen = isFrozen
    }

    public func allows(categoryID: String) -> Bool {
        !isFrozen && (allowedCategoryIDs.isEmpty || allowedCategoryIDs.contains(categoryID))
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
    /// Present only for `creditAdditional`.
    public let additional: AdditionalCardControls?
    /// The person's own freeze on a holder or debit plastic; additional cards keep theirs in
    /// `additional`, where the holder sets it.
    private let isPlasticFrozen: Bool

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        kind: CardKind,
        network: CardNetwork? = nil,
        lastFour: String? = nil,
        color: CardColor? = nil,
        additional: AdditionalCardControls? = nil,
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
        self.additional = kind == .creditAdditional ? additional : nil
        isPlasticFrozen = kind == .creditAdditional ? false : isFrozen
    }

    /// A frozen card can't be chosen to pay, so nothing gets logged on a card the person locked.
    public var isFrozen: Bool {
        additional?.isFrozen ?? isPlasticFrozen
    }

    /// The same additional card with other controls.
    public func with(additional controls: AdditionalCardControls) -> Self {
        guard let copy = try? Self(
            id: id,
            accountID: accountID,
            kind: kind,
            network: network,
            lastFour: lastFour,
            color: color,
            additional: controls,
            isFrozen: isPlasticFrozen,
        ) else { return self }
        return copy
    }

    /// The same card frozen or unfrozen; an additional card changes its controls.
    public func with(isFrozen: Bool) -> Self {
        guard let copy = try? Self(
            id: id,
            accountID: accountID,
            kind: kind,
            network: network,
            lastFour: lastFour,
            color: color,
            additional: additional.map { controls in
                AdditionalCardControls(
                    holderName: controls.holderName,
                    cycleCap: controls.cycleCap,
                    allowedCategoryIDs: controls.allowedCategoryIDs,
                    defaultCategoryID: controls.defaultCategoryID,
                    alertEachPurchase: controls.alertEachPurchase,
                    alertNearCap: controls.alertNearCap,
                    isFrozen: isFrozen,
                )
            },
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
