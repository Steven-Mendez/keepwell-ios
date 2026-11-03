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
    var onOpen: ((Card) -> Void)?
    let onLink: () -> Void

    private var bank: String {
        deposit.account.bank ?? deposit.account.name
    }

    /// The account's own name when the bank already heads the card, so it isn't lost.
    private var caption: String? {
        deposit.account.bank == nil ? nil : deposit.account.name
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
                CardStack(deposit.debitCards, label: accessibilityLabel, onTap: onOpen, art: { card, isFront in
                    CardDisplay.art(
                        of: card,
                        kind: .debit,
                        bank: bank,
                        badge: isFront ? .amount(formatter.string(deposit.balance)) : card.lastFour.map { .tag("•••• \($0)") },
                        caption: caption,
                        showsFace: isFront,
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

/// Cash as a banknote, with the two things a person does with it. Tapping the note opens its
/// movements, as tapping a card opens the card.
struct CashNote: View {
    let cash: AccountsOverview.Cash
    let formatter: CurrencyFormatter
    let onReconcile: () -> Void
    let onWithdraw: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Button(action: onOpen) { note }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows its movements", bundle: #bundle))
            HStack(spacing: KWSpacing.xs) {
                Button(action: onReconcile) { Text("Reconcile", bundle: #bundle) }
                    .buttonStyle(.kw(.primary, size: .medium))
                Button(action: onWithdraw) { Text("ATM withdrawal", bundle: #bundle) }
                    .buttonStyle(.kw(.secondary, size: .medium))
            }
            Button(action: onOpen) {
                HStack(spacing: KWSpacing.xs) {
                    KWIconView(.list, size: 20)
                    Text("See movements", bundle: #bundle)
                        .font(.kw(14, weight: 600, relativeTo: .subheadline))
                }
                .foregroundStyle(KWColor.Brand.link)
                .frame(minHeight: KWLayout.minTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var note: some View {
        KWBanknote(
            title: cash.account.name,
            amount: formatter.string(cash.balance, fractionDigits: 0),
            footnote: cash.principalEquivalent.map { "≈ \(formatter.string($0))" },
            currency: cash.balance.currency,
        )
    }
}
