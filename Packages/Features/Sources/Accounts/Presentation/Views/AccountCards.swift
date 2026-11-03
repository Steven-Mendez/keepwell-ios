import AccountsDomain
import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Cards fanned like Wallet: each card shows its top 76pt above the next, and the first item sits
/// in front, fully visible. Credit cards only: a bank account is a single card and needs no stack.
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

/// A bank account shown as its one debit card, with the balance on the face. The person thinks
/// of the account as its card, so there is nothing else to tap or link.
struct DepositCard: View {
    let deposit: AccountsOverview.Deposit
    let formatter: CurrencyFormatter
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            CardDisplay.art(
                of: deposit.debitCard,
                kind: .debit,
                bank: deposit.account.bank ?? deposit.account.name,
                badge: .amount(formatter.string(deposit.balance)),
                // The account's own name when the bank already heads the card, so it isn't lost.
                caption: deposit.account.bank == nil ? nil : deposit.account.name,
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let name = CardDisplay.name(of: deposit.account)
        let balance = formatter.string(deposit.balance)
        guard let digits = deposit.debitCard?.lastFour else {
            return String(localized: "\(name) debit card, \(balance)", bundle: #bundle)
        }
        return String(localized: "\(name) debit card •••• \(digits), \(balance)", bundle: #bundle)
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
