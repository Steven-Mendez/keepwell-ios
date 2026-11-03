import AccountsDomain
import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Every card in one Wallet-style stack: each shows its top strip above the next and the last sits
/// in front, whole. Scrolling past the top piles the cards up like a deck being shuffled, and any
/// strip opens its card.
struct WalletStack: View {
    let cards: [WalletCard]
    let formatter: CurrencyFormatter
    let ownerName: String?
    let onOpen: (WalletCard) -> Void
    @State private var width: CGFloat = 358
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of each card shows above the next, as in Wallet.
    private let reveal: CGFloat = 76

    var body: some View {
        let cardHeight = width / KWComponentMetrics.cardArtRatio
        VStack(spacing: reveal - cardHeight) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                Button { onOpen(card) } label: { art(card) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(card))
                    // Only the top strip of a card behind another is visible, so it's where VoiceOver taps.
                    .accessibilityActivationPoint(UnitPoint(x: 0.5, y: 0.1))
                    .zIndex(Double(index))
                    .shadow(color: index > 0 ? .black.opacity(0.55) : .clear, radius: 12, y: -8)
                    .visualEffect { [reduceMotion] content, proxy in
                        Self.shuffle(
                            content,
                            proxy: proxy,
                            cardHeight: cardHeight,
                            tilt: index.isMultiple(of: 2) ? 2.5 : -2.5,
                            reduceMotion: reduceMotion,
                        )
                    }
                    .transition(.asymmetric(
                        insertion: .offset(y: 120).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
                    ))
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// A card that scrolls past the top stays pinned there, shrinking and tipping back as the next
    /// one slides over it, so the stack folds into a deck instead of leaving the screen.
    private nonisolated static func shuffle(
        _ content: EmptyVisualEffect,
        proxy: GeometryProxy,
        cardHeight: CGFloat,
        tilt: Double,
        reduceMotion: Bool,
    ) -> some VisualEffect {
        let minY: CGFloat = proxy.frame(in: .scrollView(axis: .vertical)).minY
        let overshoot: CGFloat = reduceMotion ? 0 : max(0, -minY)
        let progress: CGFloat = min(overshoot / cardHeight, 1)
        let pinned: CGFloat = overshoot * 0.92
        let scale: CGFloat = 1 - progress * 0.12
        let tipBack = Angle.degrees(Double(progress) * 24)
        let twist = Angle.degrees(tilt * Double(progress))
        let opacity = Double(1 - progress * 0.55)
        return content
            .offset(y: pinned)
            .scaleEffect(scale, anchor: .top)
            .rotation3DEffect(tipBack, axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
            .rotationEffect(twist, anchor: .top)
            .opacity(opacity)
    }

    private func art(_ card: WalletCard) -> some View {
        switch card {
        case let .credit(credit):
            CardDisplay.art(
                of: credit.holder,
                kind: .creditHolder,
                bank: credit.account.bank ?? credit.account.name,
                ownerName: ownerName,
                badge: .amount(formatter.joined(credit.balances)),
                caption: credit.account.bank == nil ? nil : credit.account.name,
            )
        case let .debit(deposit):
            CardDisplay.art(
                of: deposit.debitCard,
                kind: .debit,
                bank: deposit.account.bank ?? deposit.account.name,
                ownerName: ownerName,
                badge: .amount(formatter.string(deposit.balance)),
                // The account's own name when the bank already heads the card, so it isn't lost.
                caption: deposit.account.bank == nil ? nil : deposit.account.name,
            )
        case let .cash(cash):
            KWCardArt(
                palette: .lima,
                bank: cash.account.name,
                badge: .amount(formatter.string(cash.balance)),
                showsChip: false,
                showsContactless: false,
                caption: cash.principalEquivalent.map { "≈ \(formatter.string($0))" },
                kindLabel: String(localized: "Cash", bundle: #bundle),
            )
        }
    }

    private func accessibilityLabel(_ card: WalletCard) -> String {
        switch card {
        case let .credit(credit):
            let name = credit.holder.map(CardDisplay.shortName(of:)) ?? CardDisplay.name(of: credit.account)
            return String(localized: "\(name) credit card, \(formatter.joined(credit.balances))", bundle: #bundle)
        case let .debit(deposit):
            let name = CardDisplay.name(of: deposit.account)
            let balance = formatter.string(deposit.balance)
            guard let digits = deposit.debitCard?.lastFour else {
                return String(localized: "\(name) debit card, \(balance)", bundle: #bundle)
            }
            return String(localized: "\(name) debit card •••• \(digits), \(balance)", bundle: #bundle)
        case let .cash(cash):
            return String(localized: "\(cash.account.name) cash, \(formatter.string(cash.balance))", bundle: #bundle)
        }
    }
}

/// A bank account shown as its one debit card, with the balance on the face. The person thinks
/// of the account as its card, so there is nothing else to tap or link.
struct DepositCard: View {
    let deposit: AccountsOverview.Deposit
    let formatter: CurrencyFormatter
    let ownerName: String?
    let onOpen: () -> Void

    var body: some View {
        WalletStack(cards: [.debit(deposit)], formatter: formatter, ownerName: ownerName) { _ in onOpen() }
    }
}
