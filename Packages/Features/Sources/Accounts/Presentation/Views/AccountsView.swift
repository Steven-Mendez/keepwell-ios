import AccountsDomain
import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Accounts as a wallet: every card the person carries (debit, credit and cash) in one stack,
/// with chips to show one kind. Tapping a card opens it.
public struct AccountsView: View {
    @Bindable private var viewModel: AccountsViewModel
    private let onAdd: () -> Void
    private let onOpenCreditCard: (UUID) -> Void
    private let onOpenBankAccount: (UUID) -> Void
    private let onOpenCash: (UUID) -> Void
    private let formatter = CurrencyFormatter()

    public init(
        viewModel: AccountsViewModel,
        onAdd: @escaping () -> Void,
        onOpenCreditCard: @escaping (UUID) -> Void,
        onOpenBankAccount: @escaping (UUID) -> Void,
        onOpenCash: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onAdd = onAdd
        self.onOpenCreditCard = onOpenCreditCard
        self.onOpenBankAccount = onOpenBankAccount
        self.onOpenCash = onOpenCash
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if viewModel.overview != nil {
                    filters
                    WalletStack(cards: viewModel.cards, formatter: formatter, ownerName: viewModel.ownerName, onOpen: open)
                        .padding(.top, 6)
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
    }

    @ViewBuilder
    private var filters: some View {
        let options = viewModel.filters
        if !options.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: KWSpacing.xs) {
                    ForEach(options, id: \.self) { option in
                        KWChip(viewModel.title(of: option), isSelected: viewModel.filter == option) {
                            // The cards deal in again, as if the deck were reshuffled.
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                viewModel.filter = option
                            }
                        }
                    }
                }
                .padding(.horizontal, KWLayout.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -KWLayout.gutter)
        }
    }

    private func open(_ card: WalletCard) {
        switch card {
        case let .credit(credit): onOpenCreditCard(credit.id)
        case let .debit(deposit): onOpenBankAccount(deposit.id)
        case let .cash(cash): onOpenCash(cash.id)
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
            onOpenBankAccount: { _ in },
            onOpenCash: { _ in },
        )
        .onAppear { KWFonts.register() }
    }
}
