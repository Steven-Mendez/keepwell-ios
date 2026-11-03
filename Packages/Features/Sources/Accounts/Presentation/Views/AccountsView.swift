import AccountsDomain
import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Accounts: credit cards stacked like Wallet, deposit accounts with their linked methods, and cash.
public struct AccountsView: View {
    private let viewModel: AccountsViewModel
    private let onAdd: () -> Void
    private let onOpenCreditCard: (UUID) -> Void
    private let onLinkCard: (UUID) -> Void
    @State private var cashAction: CashAction?
    private let formatter = CurrencyFormatter()

    enum CashAction: Identifiable {
        case reconcile(AccountsOverview.Cash)
        case withdraw(AccountsOverview.Cash)

        var id: String {
            switch self {
            case let .reconcile(cash): "reconcile-\(cash.id)"
            case let .withdraw(cash): "withdraw-\(cash.id)"
            }
        }
    }

    public init(
        viewModel: AccountsViewModel,
        onAdd: @escaping () -> Void,
        onOpenCreditCard: @escaping (UUID) -> Void,
        onLinkCard: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onAdd = onAdd
        self.onOpenCreditCard = onOpenCreditCard
        self.onLinkCard = onLinkCard
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let overview = viewModel.overview {
                    if !overview.creditCards.isEmpty {
                        KWSectionHeader(String(localized: "Credit cards", bundle: #bundle), style: .large) {
                            Text("Tap to see details", bundle: #bundle)
                                .font(KWTextStyle.label.font.weight(.regular))
                                .foregroundStyle(KWColor.Text.muted)
                        }
                        .padding(.top, 6)
                        CreditCardStack(cards: overview.creditCards, formatter: formatter, onOpen: onOpenCreditCard)
                    }
                    if !overview.deposits.isEmpty {
                        KWSectionHeader(String(localized: "Deposits", bundle: #bundle), style: .large).padding(.top, 10)
                        ForEach(overview.deposits) { deposit in
                            DepositCard(deposit: deposit, formatter: formatter) { onLinkCard(deposit.id) }
                        }
                    }
                    if !overview.cash.isEmpty {
                        KWSectionHeader(String(localized: "Cash", bundle: #bundle), style: .large).padding(.top, 10)
                        ForEach(overview.cash) { cash in
                            CashCard(cash: cash, formatter: formatter) {
                                cashAction = .reconcile(cash)
                            } onWithdraw: {
                                cashAction = .withdraw(cash)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
        .sheet(item: $cashAction) { action in
            Group {
                switch action {
                case let .reconcile(cash):
                    ReconcileCashSheet(viewModel: viewModel, cash: cash, formatter: formatter) { cashAction = nil }
                case let .withdraw(cash):
                    WithdrawCashSheet(
                        viewModel: viewModel,
                        cash: cash,
                        sources: viewModel.overview?.deposits ?? [],
                        principal: viewModel.overview?.settings.principal ?? "USD",
                    ) { cashAction = nil }
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(KWColor.Surface.bg)
        }
    }

    /// One localized sentence with only the amount emphasized, since word order differs per language.
    private func netWorthText(_ netWorth: Money) -> AttributedString {
        let amount = formatter.string(netWorth)
        var text = AttributedString(String(localized: "Net worth \(amount)", bundle: #bundle))
        if let range = text.range(of: amount) {
            text[range].foregroundColor = KWColor.Text.primary
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    private var header: some View {
        KWLargeTitleHeader(String(localized: "Accounts", bundle: #bundle), alignment: .top) {
            if let overview = viewModel.overview {
                Text(netWorthText(overview.netWorth))
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .monospacedDigit()
            }
        } trailing: {
            KWCircleButton(
                .plus,
                style: .white,
                accessibilityLabel: String(localized: "Add account or card", bundle: #bundle),
                action: onAdd,
            )
        }
    }
}

/// Credit cards fanned like Wallet: each card shows its top 76pt above the next, and the first
/// account (the oldest) sits in front, fully visible.
struct CreditCardStack: View {
    private let cards: [AccountsOverview.CreditCard]
    private let formatter: CurrencyFormatter
    private let onOpen: (UUID) -> Void
    @State private var width: CGFloat = 358

    init(cards: [AccountsOverview.CreditCard], formatter: CurrencyFormatter, onOpen: @escaping (UUID) -> Void) {
        // Drawn back to front, so the front card goes last.
        self.cards = cards.reversed()
        self.formatter = formatter
        self.onOpen = onOpen
    }

    private let reveal: CGFloat = 76

    var body: some View {
        let cardHeight = width / KWComponentMetrics.cardArtRatio
        ZStack(alignment: .top) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let isFront = index == cards.count - 1
                Button { onOpen(card.id) } label: {
                    art(card, isFront: isFront)
                }
                .buttonStyle(.plain)
                .shadow(color: index > 0 ? .black.opacity(0.55) : .clear, radius: 12, y: -8)
                .offset(y: CGFloat(index) * reveal)
                .accessibilityLabel(CardDisplay.shortName(of: card.holder ?? Self.placeholderCard(for: card)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight + reveal * CGFloat(max(cards.count - 1, 0)), alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func art(_ card: AccountsOverview.CreditCard, isFront: Bool) -> KWCardArt {
        let palette = CardDisplay.palette(for: card.holder?.color)
        let plastics = card.plasticCount
        return KWCardArt(
            palette: palette,
            bank: card.account.bank ?? card.account.name,
            badge: .amount(formatter.joined(card.balances)),
            showsChip: isFront,
            caption: isFront ? String(localized: "Credit · \(plastics) cards", bundle: #bundle) : nil,
            lastFour: isFront ? card.holder?.lastFour : nil,
            network: isFront ? CardDisplay.wordmark(for: card.holder?.network) : nil,
        )
    }

    private static func placeholderCard(for card: AccountsOverview.CreditCard) -> Card {
        // Accounts created without a plastic still need an accessible name.
        (try? Card(accountID: card.account.id, kind: .creditHolder)) ?? fallbackCard
    }

    private static let fallbackCard: Card = {
        guard let card = try? Card(accountID: UUID(), kind: .creditHolder) else { preconditionFailure("valid card") }
        return card
    }()
}

struct DepositCard: View {
    let deposit: AccountsOverview.Deposit
    let formatter: CurrencyFormatter
    let onLink: () -> Void

    private var linkedMethods: String {
        let count = deposit.methods.count
        return String(localized: "\(count) linked methods", bundle: #bundle)
    }

    private func debitName(_ method: Card) -> String {
        let network = CardDisplay.networkName(method.network)
        return String(localized: "\(network) Debit", bundle: #bundle)
    }

    var body: some View {
        KWGroupedCard(verticalPadding: KWSpacing.xxs) {
            HStack(spacing: KWSpacing.sm) {
                KWTitleSubtitle(
                    CardDisplay.name(of: deposit.account),
                    subtitle: "\(deposit.balance.currency) · \(linkedMethods)",
                    titleFont: KWTextStyle.heading.font,
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(formatter.string(deposit.balance))
                    .font(.kw(17, weight: 800))
                    .monospacedDigit()
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
            ForEach(deposit.methods) { method in
                HStack(spacing: KWSpacing.sm) {
                    KWMiniCard(CardDisplay.miniCard(for: method))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(CardDisplay.methodTitle(method, account: deposit.account))
                            .font(.kw(14, weight: 600, relativeTo: .subheadline))
                        if method.kind == .debit {
                            Text(debitName(method))
                                .font(KWTextStyle.captionSm.font)
                                .foregroundStyle(KWColor.Text.muted)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            Button(action: onLink) {
                HStack(spacing: KWSpacing.sm) {
                    KWMiniCard(.add)
                    Text("Link another card", bundle: #bundle)
                        .font(.kw(14, weight: 600, relativeTo: .subheadline))
                        .foregroundStyle(KWColor.Brand.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, KWSpacing.sm)
        }
    }
}

struct CashCard: View {
    let cash: AccountsOverview.Cash
    let formatter: CurrencyFormatter
    let onReconcile: () -> Void
    let onWithdraw: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: KWSpacing.sm) {
                KWIconView(.wallet, size: 22)
                    .foregroundStyle(KWColor.Text.onPositive)
                    .frame(width: 44, height: 44)
                    .background(KWColor.State.positive, in: Circle())
                KWTitleSubtitle(cash.account.name, subtitle: subtitle, titleFont: KWTextStyle.heading.font)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(formatter.string(cash.balance, fractionDigits: 0))
                    .font(.kw(17, weight: 800))
                    .monospacedDigit()
            }
            HStack(spacing: KWSpacing.xs) {
                Button(action: onReconcile) { Text("Reconcile", bundle: #bundle) }
                    .buttonStyle(.kw(.primary, size: .medium))
                Button(action: onWithdraw) { Text("ATM withdrawal", bundle: #bundle) }
                    .buttonStyle(.kw(.secondary, size: .medium))
            }
        }
        .padding(KWSpacing.md)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
    }

    private var subtitle: String {
        guard let equivalent = cash.principalEquivalent else { return cash.balance.currency }
        return "\(cash.balance.currency) · ≈ \(formatter.string(equivalent))"
    }
}

#Preview {
    AccountsPreview()
}

private struct AccountsPreview: View {
    @State private var viewModel = AccountsPreviewData.viewModel()

    var body: some View {
        AccountsView(viewModel: viewModel, onAdd: {}, onOpenCreditCard: { _ in }, onLinkCard: { _ in })
            .onAppear { KWFonts.register() }
    }
}
