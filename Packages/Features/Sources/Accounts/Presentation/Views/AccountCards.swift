import AccountsDomain
import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Cards fanned like Wallet: each card shows its top 76pt above the next, and the first item sits
/// in front, fully visible. Shared by credit cards and by each bank account's debit cards so both
/// read as the same physical object.
struct CardStack<Item: Identifiable, Art: View>: View {
    private let items: [Item]
    private let art: (Item, Bool) -> Art
    private let label: (Item) -> String
    private let onTap: ((Item) -> Void)?
    @State private var width: CGFloat = 358

    private let reveal: CGFloat = 76

    init(
        _ items: [Item],
        label: @escaping (Item) -> String,
        onTap: ((Item) -> Void)? = nil,
        @ViewBuilder art: @escaping (_ item: Item, _ isFront: Bool) -> Art,
    ) {
        // Drawn back to front, so the front item goes last.
        self.items = items.reversed()
        self.label = label
        self.onTap = onTap
        self.art = art
    }

    var body: some View {
        let cardHeight = width / KWComponentMetrics.cardArtRatio
        ZStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isFront = index == items.count - 1
                Group {
                    if let onTap {
                        Button { onTap(item) } label: { art(item, isFront) }
                            .buttonStyle(.plain)
                    } else {
                        art(item, isFront)
                    }
                }
                .shadow(color: index > 0 ? .black.opacity(0.55) : .clear, radius: 12, y: -8)
                .offset(y: CGFloat(index) * reveal)
                .accessibilityLabel(label(item))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight + reveal * CGFloat(max(items.count - 1, 0)), alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// A bank account shown through its debit cards. An account with no card yet still appears, as
/// an empty card slot that adds one, because the person thinks of the account as its card.
struct DepositCards: View {
    let deposit: AccountsOverview.Deposit
    let formatter: CurrencyFormatter
    let onLink: () -> Void

    private var bank: String {
        deposit.account.bank ?? deposit.account.name
    }

    /// "Debit · Savings" when the bank already names the card, so the account's own name isn't lost.
    private var caption: String {
        guard deposit.account.bank != nil else { return String(localized: "Debit", bundle: #bundle) }
        let name = deposit.account.name
        return String(localized: "Debit · \(name)", bundle: #bundle)
    }

    var body: some View {
        if deposit.debitCards.isEmpty {
            EmptyCardSlot(
                title: CardDisplay.name(of: deposit.account),
                amount: formatter.string(deposit.balance),
                action: onLink,
            )
        } else {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                CardStack(deposit.debitCards, label: accessibilityLabel, art: { card, isFront in
                    KWCardArt(
                        palette: CardDisplay.palette(for: card.color),
                        bank: bank,
                        badge: isFront ? .amount(formatter.string(deposit.balance)) : card.lastFour.map { .tag("•••• \($0)") },
                        showsChip: isFront,
                        caption: isFront ? caption : nil,
                        lastFour: isFront ? card.lastFour : nil,
                        network: isFront ? CardDisplay.wordmark(for: card.network) : nil,
                        isFrozen: card.isFrozen,
                    )
                })
                Button(action: onLink) {
                    HStack(spacing: KWSpacing.xs) {
                        KWIconView(.addCard, size: 20)
                        Text("Link another card", bundle: #bundle)
                            .font(.kw(14, weight: 600, relativeTo: .subheadline))
                    }
                    .foregroundStyle(KWColor.Brand.link)
                    .frame(minHeight: KWLayout.minTouch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func accessibilityLabel(_ card: Card) -> String {
        let name = CardDisplay.name(of: deposit.account)
        let digits = card.lastFour ?? ""
        let balance = formatter.string(deposit.balance)
        return String(localized: "\(name) debit card •••• \(digits), \(balance)", bundle: #bundle)
    }
}

/// A card-shaped dashed slot for a bank account that has no card linked yet.
struct EmptyCardSlot: View {
    let title: String
    let amount: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KWRadius.card, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(.kw(17, weight: 800))
                        .tracking(-0.3)
                    Spacer(minLength: KWSpacing.xs)
                    Text(amount)
                        .font(.kw(14, weight: 700, relativeTo: .subheadline))
                        .monospacedDigit()
                }
                .lineLimit(1)
                .foregroundStyle(KWColor.Text.primary)
                Spacer(minLength: 0)
                VStack(spacing: KWSpacing.xs) {
                    KWIconView(.addCard, size: 28)
                    Text("Add a debit card", bundle: #bundle)
                        .font(.kw(15, weight: 600, relativeTo: .subheadline))
                }
                .foregroundStyle(KWColor.Brand.link)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .padding(KWSpacing.lg)
            .aspectRatio(KWComponentMetrics.cardArtRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(KWColor.Surface.surface, in: shape)
            .overlay(shape.strokeBorder(KWColor.Surface.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Cash drawn as a banknote rather than a card: no chip or digits, a framed note with a medallion,
/// so it is never mistaken for something you swipe.
struct CashNote: View {
    let cash: AccountsOverview.Cash
    let formatter: CurrencyFormatter
    let onReconcile: () -> Void
    let onWithdraw: () -> Void

    var body: some View {
        VStack(spacing: KWSpacing.sm) {
            note
            HStack(spacing: KWSpacing.xs) {
                Button(action: onReconcile) { Text("Reconcile", bundle: #bundle) }
                    .buttonStyle(.kw(.primary, size: .medium))
                Button(action: onWithdraw) { Text("ATM withdrawal", bundle: #bundle) }
                    .buttonStyle(.kw(.secondary, size: .medium))
            }
        }
    }

    private var note: some View {
        let shape = RoundedRectangle(cornerRadius: KWRadius.input, style: .continuous)
        return ZStack {
            KWColor.CardArt.verde.largeGradient
            medallion
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, KWSpacing.xl)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: KWSpacing.xs) {
                    KWIconView(.wallet, size: 18)
                    Text(cash.account.name)
                        .font(.kw(17, weight: 800))
                        .tracking(-0.3)
                }
                Spacer(minLength: KWSpacing.sm)
                Text(formatter.string(cash.balance, fractionDigits: 0))
                    .font(.kw(28, weight: 800))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                if let equivalent = cash.principalEquivalent {
                    Text("≈ \(formatter.string(equivalent))")
                        .font(KWTextStyle.captionSm.font)
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(KWSpacing.lg)
        }
        .foregroundStyle(KWColor.Text.primary)
        .aspectRatio(2.2, contentMode: .fit)
        .clipShape(shape)
        // The inner frame is what makes it read as a note.
        .overlay(shape.inset(by: KWSpacing.xs).strokeBorder(.white.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var medallion: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 10)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1).padding(16)
            Text(cash.balance.currency)
                .font(.kw(15, weight: 800))
                .opacity(0.85)
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
    }
}
