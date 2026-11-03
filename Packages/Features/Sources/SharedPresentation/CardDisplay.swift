import DesignSystem
import Domain

/// How cards and accounts read on screen, shared by every feature that lists them.
public enum CardDisplay {
    public static func palette(for color: CardColor?) -> KWColor.CardArt {
        switch color {
        case .azul, nil: .azul
        case .grafito: .grafito
        case .verde: .verde
        case .violeta: .violeta
        case .coral: .coral
        case .oro: .oro
        case .lima: .lima
        }
    }

    public static func cardColor(for palette: KWColor.CardArt) -> CardColor {
        CardColor(rawValue: palette.rawValue) ?? .azul
    }

    /// The wordmark printed on card art ("VISA", "mastercard").
    public static func wordmark(for network: CardNetwork?) -> String {
        switch network {
        case .visa: "VISA"
        case .mastercard: "mastercard"
        case .amex: "AMEX"
        case .other, nil: ""
        }
    }

    public static func networkName(_ network: CardNetwork?) -> String {
        switch network {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .amex: "Amex"
        case .other, nil: "Otra"
        }
    }

    /// "Banco Uno Ahorro": the bank followed by the account's own name.
    public static func name(of account: Account) -> String {
        [account.bank, account.name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// "Mastercard ··4321".
    public static func shortName(of card: Card) -> String {
        [networkName(card.network), card.lastFour.map { "··\($0)" }].compactMap(\.self).joined(separator: " ")
    }

    /// Title of a payment method row ("Débito •••• 3922", "Transferencias Banco Uno").
    public static func methodTitle(_ card: Card, account: Account?) -> String {
        switch card.kind {
        case .debit: "Débito •••• \(card.lastFour ?? "")"
        case .transfer: "Transferencias \(account?.bank ?? account?.name ?? "")".trimmingCharacters(in: .whitespaces)
        case .creditHolder: "Titular"
        case .creditAdditional: card.additional?.holderName ?? "Adicional"
        }
    }

    public static func miniCard(for card: Card) -> KWMiniCard.Style {
        card.kind == .transfer ? .transfer : .palette(palette(for: card.color), chip: true)
    }
}
