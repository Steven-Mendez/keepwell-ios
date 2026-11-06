import AccountsDomain
import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Every card in one Wallet-style stack: each shows its top strip above the next and the last sits
/// in front, whole. The deck rolls like an endless scroll, one card at a time: dragging over it turns
/// a card per strip in either direction, and tapping a card behind rolls it to the front, each turn a
/// little quicker than the last. The front card opens. Scrolling past the top piles the cards up like
/// a deck being shuffled.
struct WalletStack: View {
    let cards: [WalletCard]
    let formatter: CurrencyFormatter
    let ownerName: String?
    let onOpen: (WalletCard) -> Void
    @State private var width: CGFloat = 358
    /// The card turned to the front; nil keeps the deck in its own order, the last card in front.
    @State private var frontID: UUID?
    @State private var roll: Task<Void, Never>?
    /// Turns already taken by the drag in progress, so each strip of travel turns exactly one card.
    @State private var draggedTurns = 0
    /// When a drag last moved, since lifting the finger off a drag also lands on a card's button and
    /// would open it.
    @State private var lastDrag = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of each card shows above the next, as in Wallet.
    private let reveal: CGFloat = 76

    /// The deck as drawn, turned like a wheel until the front card is last: the cards that were ahead
    /// of it sit at the back in their order, so the deck's order never breaks.
    private var deck: [WalletCard] {
        guard cards.count > 1, let at = cards.firstIndex(where: { $0.id == frontID }) else { return cards }
        return Array(cards[(at + 1)...] + cards[...at])
    }

    var body: some View {
        let cardHeight = width / KWComponentMetrics.cardArtRatio
        let deck = deck
        VStack(spacing: reveal - cardHeight) {
            ForEach(Array(deck.enumerated()), id: \.element.id) { index, card in
                Button { tap(card, at: index, in: deck) } label: { art(card) }
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
        .contentShape(Rectangle())
        .simultaneousGesture(cards.count > 1 ? scroll : nil)
        .sensoryFeedback(.selection, trigger: frontID)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // A filter can take the front card away; the new deck starts in its own order.
        .onChange(of: cards.map(\.id)) {
            roll?.cancel()
            if !cards.contains(where: { $0.id == frontID }) {
                frontID = nil
            }
        }
        .onDisappear { roll?.cancel() }
    }

    /// Dragging down turns the front card round to the back; dragging up brings the back card forward.
    /// It runs alongside the screen's scroll view, which would otherwise take every vertical drag.
    private var scroll: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                roll?.cancel()
                lastDrag = .now
                let turns = Int((value.translation.height / reveal).rounded(.towardZero))
                while draggedTurns < turns {
                    turn(forward: true, duration: Self.turnDuration)
                    draggedTurns += 1
                }
                while draggedTurns > turns {
                    turn(forward: false, duration: Self.turnDuration)
                    draggedTurns -= 1
                }
            }
            .onEnded { _ in
                draggedTurns = 0
                lastDrag = .now
            }
    }

    private func tap(_ card: WalletCard, at index: Int, in deck: [WalletCard]) {
        guard Date.now.timeIntervalSince(lastDrag) > 0.3 else { return }
        let steps = deck.count - 1 - index
        guard steps > 0 else {
            onOpen(card)
            return
        }
        roll?.cancel()
        guard !reduceMotion else {
            frontID = card.id
            return
        }
        roll = Task {
            var pace = 1.0
            for step in 0 ..< steps {
                if step > 0 {
                    try? await Task.sleep(for: .seconds(max(Self.minTurnInterval, Self.turnInterval * pace)))
                }
                guard !Task.isCancelled else { return }
                turn(forward: true, duration: max(Self.minTurnDuration, Self.turnDuration * pace))
                pace *= Self.turnAcceleration
            }
        }
    }

    /// One turn of the deck. Forward sends the front card round to the back and steps the rest down a
    /// slot; backward brings the back card round to the front.
    private func turn(forward: Bool, duration: Double) {
        let deck = deck
        guard deck.count > 1 else { return }
        let next = forward ? deck[deck.count - 2] : deck[0]
        // The same even ease-out as the web deck, with no spring overshoot, so nothing bounces.
        let animation: Animation? = reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: duration)
        withAnimation(animation) { frontID = next.id }
    }

    /// The first turn's length, in seconds; a long roll speeds up from here.
    private static let turnDuration = 0.38
    /// The wait before the second turn of a roll, a little under a turn so it flows.
    private static let turnInterval = 0.26
    /// Each turn of a roll takes this share of the one before, so it speeds up instead of dragging.
    private static let turnAcceleration = 0.9
    /// The fastest a turn may get, so the cards still read as moving rather than jumping.
    private static let minTurnDuration = 0.28
    private static let minTurnInterval = 0.19

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
