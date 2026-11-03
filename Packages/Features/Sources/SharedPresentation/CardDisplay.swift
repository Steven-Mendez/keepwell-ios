import DesignSystem
import Domain
import Foundation

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
        case .other, nil: String(localized: "network.other", defaultValue: "Other", bundle: #bundle)
        }
    }

    /// "Bank One Ahorro": the bank followed by the account's own name.
    public static func name(of account: Account) -> String {
        [account.bank, account.name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// "Mastercard ··4321".
    public static func shortName(of card: Card) -> String {
        [networkName(card.network), card.lastFour.map { "··\($0)" }].compactMap(\.self).joined(separator: " ")
    }

    /// How a movement names what paid it: "Debit •••• 3922", "Bank One · Bank transfer",
    /// "Visa •••• 3141". Credit cards show their network and digits rather than the "holder" role,
    /// which only means something next to the card's additionals.
    public static func methodTitle(_ card: Card, account: Account?) -> String {
        let lastFour = card.lastFour ?? ""
        return switch card.kind {
        case .debit: String(localized: "Debit •••• \(lastFour)", bundle: #bundle)
        case .transfer: bankTransferTitle(account: account)
        case .creditHolder: cardNumber(card)
        case .creditAdditional: card.additional?.holderName ?? String(localized: "Additional", bundle: #bundle)
        }
    }

    /// "Visa •••• 3141", or just the network when the digits are unknown.
    public static func cardNumber(_ card: Card) -> String {
        [networkName(card.network), card.lastFour.map { "•••• \($0)" }].compactMap(\.self).joined(separator: " ")
    }

    /// "Bank One · Bank transfer": a payment charged straight to the account, with no card.
    public static func bankTransferTitle(account: Account?) -> String {
        let method = String(localized: "Bank transfer", bundle: #bundle)
        let owner = (account?.bank ?? account?.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        return owner.isEmpty ? method : "\(owner) · \(method)"
    }

    public static func miniCard(for card: Card) -> KWMiniCard.Style {
        card.kind == .transfer ? .transfer : .palette(palette(for: card.color), chip: true)
    }
}
