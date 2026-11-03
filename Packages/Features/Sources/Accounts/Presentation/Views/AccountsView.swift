import AccountsDomain
import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Accounts, shown through what the person carries: credit cards and each bank account's debit
/// cards stacked like Wallet, and cash as a banknote.
public struct AccountsView: View {
    private let viewModel: AccountsViewModel
    private let onAdd: () -> Void
    private let onOpenCreditCard: (UUID) -> Void
    private let onOpenDebitCard: (UUID) -> Void
    private let onLinkCard: (UUID) -> Void
    private let onOpenAccountMovements: (UUID) -> Void
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
        onOpenDebitCard: @escaping (UUID) -> Void,
        onLinkCard: @escaping (UUID) -> Void,
        onOpenAccountMovements: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onAdd = onAdd
        self.onOpenCreditCard = onOpenCreditCard
        self.onOpenDebitCard = onOpenDebitCard
        self.onLinkCard = onLinkCard
        self.onOpenAccountMovements = onOpenAccountMovements
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
                        KWSectionHeader(String(localized: "Debit cards", bundle: #bundle), style: .large)
                            .padding(.top, 10)
                        ForEach(overview.deposits) { deposit in
                            DepositCards(
                                deposit: deposit,
                                formatter: formatter,
                                onOpen: { onOpenDebitCard($0.id) },
                                onLink: { onLinkCard(deposit.id) },
                            )
                        }
                    }
                    cashSection(overview.cash)
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

    @ViewBuilder
    private func cashSection(_ notes: [AccountsOverview.Cash]) -> some View {
        if !notes.isEmpty {
            KWSectionHeader(String(localized: "Cash", bundle: #bundle), style: .large).padding(.top, 10)
            ForEach(notes) { cash in
                CashNote(cash: cash, formatter: formatter) {
                    cashAction = .reconcile(cash)
                } onWithdraw: {
                    cashAction = .withdraw(cash)
                } onOpen: {
                    onOpenAccountMovements(cash.id)
                }
            }
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

/// Credit cards in a Wallet stack; the first account (the oldest) sits in front.
struct CreditCardStack: View {
    let cards: [AccountsOverview.CreditCard]
    let formatter: CurrencyFormatter
    let onOpen: (UUID) -> Void

    var body: some View {
        CardStack(
            cards,
            label: { CardDisplay.shortName(of: $0.holder ?? Self.placeholderCard(for: $0)) },
            onTap: { onOpen($0.id) },
            art: { card, isFront in art(card, isFront: isFront) },
        )
    }

    private func art(_ card: AccountsOverview.CreditCard, isFront: Bool) -> KWCardArt {
        CardDisplay.art(
            of: card.holder,
            kind: .creditHolder,
            bank: card.account.bank ?? card.account.name,
            badge: .amount(formatter.joined(card.balances)),
            caption: caption(card),
            showsFace: isFront,
        )
    }

    /// The account's own name when the bank heads the card, and how many plastics share it.
    private func caption(_ card: AccountsOverview.CreditCard) -> String? {
        let name = card.account.bank == nil ? nil : card.account.name
        let plastics = card.plasticCount
        let count = plastics > 1 ? String(localized: "\(plastics) cards", bundle: #bundle) : nil
        let parts = [name, count].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

#Preview {
    AccountsPreview()
}

private struct AccountsPreview: View {
    @State private var viewModel = AccountsPreviewData.viewModel()

    var body: some View {
        AccountsView(
            viewModel: viewModel,
            onAdd: {},
            onOpenCreditCard: { _ in },
            onOpenDebitCard: { _ in },
            onLinkCard: { _ in },
            onOpenAccountMovements: { _ in },
        )
        .onAppear { KWFonts.register() }
    }
}
