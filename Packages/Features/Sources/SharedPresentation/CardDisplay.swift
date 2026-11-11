import DesignSystem
import Domain
import Foundation

/// How cards and accounts read on screen, shared by every feature that lists them.
public enum CardDisplay {
    public static func palette(for color: CardColor?) -> KWColor.CardArt {
        switch color {
        case .azul, nil: .azul
        case .grafito: .grafito
        case .platino: .platino
        case .verde: .verde
        case .violeta: .violeta
        case .coral: .coral
        case .rojo: .rojo
        case .oro: .oro
        case .lima: .lima
        }
    }

    public static func cardColor(for palette: KWColor.CardArt) -> CardColor {
        CardColor(rawValue: palette.rawValue) ?? .azul
    }

    /// The colors offered for a card. A card painted in a color no longer offered keeps it at the
    /// end of the row, so opening the picker doesn't silently change it.
    public static func selectableColors(keeping current: CardColor? = nil) -> [CardColor] {
        let offered = KWColor.CardArt.selectable.map(cardColor(for:))
        guard let current, !offered.contains(current) else { return offered }
        return offered + [current]
    }

    /// The network mark printed on card art; `nil` for networks without one.
    public static func networkMark(for network: CardNetwork?) -> KWCardNetwork? {
        switch network {
        case .visa: .visa
        case .mastercard: .mastercard
        case .amex: .amex
        case .other, nil: nil
        }
    }

    /// How the network groups the full card number: Amex prints 15 digits as 4-6-5.
    public static func numberGroups(for network: CardNetwork?) -> [Int] {
        network == .amex ? [4, 6, 5] : [4, 4, 4, 4]
    }

    /// "Debit" or "Credit", as printed under the network mark.
    public static func kindLabel(_ kind: CardKind) -> String {
        switch kind {
        case .debit, .transfer: String(localized: "Debit", bundle: #bundle)
        case .creditHolder: String(localized: "Credit", bundle: #bundle)
        }
    }

    /// The art of a real plastic, so every screen prints a card the same way. `showsFace: false`
    /// leaves only the header, for a card tucked behind another in a stack. `ownerName` is the
    /// person's own name, printed on their cards.
    public static func art(
        of card: Card?,
        kind: CardKind,
        bank: String,
        ownerName: String? = nil,
        badge: KWCardArt.Badge? = nil,
        caption: String? = nil,
        showsFace: Bool = true,
        showsShadow: Bool = true,
    ) -> KWCardArt {
        KWCardArt(
            palette: palette(for: card?.color),
            bank: bank,
            badge: badge,
            showsChip: showsFace,
            holder: showsFace ? holderName(of: card, kind: kind, ownerName: ownerName) : nil,
            caption: showsFace ? caption : nil,
            lastFour: showsFace ? card?.lastFour : nil,
            numberGroups: numberGroups(for: card?.network),
            network: showsFace ? networkMark(for: card?.network) : nil,
            kindLabel: showsFace ? kindLabel(card?.kind ?? kind) : nil,
            showsShadow: showsShadow,
        )
    }

    /// "STEVEN" on the owner's debit and credit cards, uppercased as banks emboss it.
    public static func holderName(of card: Card?, kind: CardKind, ownerName: String?) -> String? {
        switch card?.kind ?? kind {
        case .debit, .creditHolder: ownerName.flatMap(PreferredName.normalized)?.uppercased(with: .current)
        case .transfer: nil
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

    /// "Premia ··0633" when the plastic has a product name, else "Mastercard ··4321".
    public static func shortName(of card: Card) -> String {
        [card.productName ?? networkName(card.network), card.lastFour.map { "··\($0)" }].compactMap(\.self).joined(separator: " ")
    }

    /// The "Card number" row's value: "Visa ··1234", or `nil` while neither is known.
    public static func numberSummary(of card: Card) -> String? {
        let parts = [card.network.map { networkName($0) }, card.lastFour.map { "··\($0)" }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "09/28", as the plastic prints it.
    public static func expiry(_ expiry: CardExpiry) -> String {
        String(format: "%02d/%02d", expiry.month, expiry.year % 100)
    }

    /// The "Product and expiry" row's value: product and expiry, or `nil` while neither is known.
    public static func detailsSummary(of card: Card) -> String? {
        let parts = [card.productName, card.expiry.map(expiry)].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// How a movement names what paid it: "Debit •••• 3922", "Bank One · Bank transfer",
    /// "Visa •••• 3141". Credit cards show their network and digits.
    public static func methodTitle(_ card: Card, account: Account?) -> String {
        switch card.kind {
        case .debit: debitTitle(card)
        case .transfer: bankTransferTitle(account: account)
        case .creditHolder: cardNumber(card)
        }
    }

    /// "Debit •••• 3922", or "Debit card" for a bank account's card saved without its digits.
    public static func debitTitle(_ card: Card) -> String {
        guard let lastFour = card.lastFour else { return String(localized: "Debit card", bundle: #bundle) }
        return String(localized: "Debit •••• \(lastFour)", bundle: #bundle)
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
