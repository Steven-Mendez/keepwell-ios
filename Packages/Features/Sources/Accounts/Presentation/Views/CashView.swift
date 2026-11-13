import AccountsDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// A cash account as one screen, laid out like a bank account's: the plastic cash is shown as, its
/// balance, rename, the latest movements and, set apart at the end, deleting the account.
public struct CashView: View {
    private let viewModel: CashViewModel
    private let onBack: () -> Void
    private let onSeeAllMovements: (UUID) -> Void
    @State private var isRenaming = false
    @State private var isConfirmingDeletion = false
    @State private var isClosing = false

    /// `onSeeAllMovements` opens the movement list filtered to the account it receives.
    public init(
        viewModel: CashViewModel,
        onBack: @escaping () -> Void,
        onSeeAllMovements: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onSeeAllMovements = onSeeAllMovements
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.lg) {
                KWNavigationHeader(String(localized: "Cash", bundle: #bundle), buttonStyle: .translucent, onBack: onBack)
                if let detail = viewModel.detail {
                    closedBanner(detail.account)
                    CardHero(art: art(detail), name: detail.account.name)
                    BalanceHeader(
                        String(localized: "Cash", bundle: #bundle),
                        amount: viewModel.balance(detail),
                        footnote: viewModel.equivalent(detail),
                    )
                    .padding(.top, -KWSpacing.sm)
                    actions
                    manage(detail)
                    latest(detail)
                    lifecycle(detail.account)
                } else if viewModel.state == .failed {
                    Text("We couldn't load this account.", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, 28)
            .background(alignment: .top) { glow }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .accountClosingSheet(
            viewModel.closing,
            accountName: viewModel.detail.map { CardDisplay.name(of: $0.account) } ?? "",
            isPresented: $isClosing,
        ) {
            Task { await viewModel.load() }
        }
        .sheet(isPresented: $isRenaming, onDismiss: viewModel.clearError) {
            if let detail = viewModel.detail {
                CardNameSheet(
                    name: detail.account.name,
                    errorMessage: viewModel.errorMessage,
                    isSaving: viewModel.isSaving,
                    onSave: viewModel.rename(to:),
                    onClose: { isRenaming = false },
                )
                .presentationDetents([.large])
                .presentationBackground(KWColor.Surface.bg)
            }
        }
        .confirmationDialog(
            viewModel.detail.map(viewModel.deleteTitle) ?? "",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        onBack()
                    }
                }
            } label: {
                Text("Delete account", bundle: #bundle)
            }
            closeInsteadButton
        } message: {
            deleteMessage
        }
    }

    /// Cash is the lima plastic the wallet shows it as, without chip or contactless.
    private func art(_ detail: CashDetail) -> KWCardArt {
        KWCardArt(
            palette: .lima,
            bank: detail.account.name,
            showsChip: false,
            showsContactless: false,
            kindLabel: String(localized: "Cash", bundle: #bundle),
        )
    }

    private var glow: some View {
        LinearGradient(
            colors: [Color(hex: KWColor.CardArt.lima.hexStops.end).opacity(0.55), KWColor.Surface.bg],
            startPoint: .top,
            endPoint: .bottom,
        )
        .frame(height: 460)
    }

    private var actions: some View {
        KWActionButton(String(localized: "Edit name", bundle: #bundle), icon: .pencil) { isRenaming = true }
            .frame(maxWidth: KWComponentMetrics.actionPairWidth / 2)
            .frame(maxWidth: .infinity)
    }

    private func manage(_ detail: CashDetail) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            KWSectionHeader(String(localized: "Manage account", bundle: #bundle), style: .large)
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                CardManageRow(String(localized: "Edit name", bundle: #bundle), icon: .pencil, value: detail.account.name) {
                    isRenaming = true
                }
            }
        }
    }

    @ViewBuilder
    private var closeInsteadButton: some View {
        if let detail = viewModel.detail, viewModel.offersCloseInstead(detail) {
            Button(AccountClosingText.closeInstead) { isClosing = true }
        }
    }

    @ViewBuilder
    private var deleteMessage: some View {
        if let detail = viewModel.detail {
            if viewModel.offersCloseInstead(detail) {
                Text(verbatim: "\(viewModel.deleteMessage(detail)) \(AccountClosingText.closeInsteadHint)")
            } else {
                Text(viewModel.deleteMessage(detail))
            }
        }
    }

    @ViewBuilder
    private func closedBanner(_ account: Account) -> some View {
        if let closing = viewModel.closing, let closedAt = account.closedAt {
            ClosedAccountBanner(model: closing, closedAt: closedAt) {
                Task { await viewModel.load() }
            }
        }
    }

    /// Apart from the edits, so neither is tapped on the way to another row.
    private func lifecycle(_ account: Account) -> some View {
        AccountLifecycleRows(
            canClose: viewModel.closing != nil && account.isOpen,
            deleteTitle: String(localized: "Delete account", bundle: #bundle),
            onClose: { isClosing = true },
            onDelete: { isConfirmingDeletion = true },
        )
    }

    @ViewBuilder
    private func latest(_ detail: CashDetail) -> some View {
        if let display = viewModel.display {
            LatestMovementsSection(
                String(localized: "Latest movements", bundle: #bundle),
                transactions: detail.latestTransactions,
                emptyMessage: String(localized: "No movements on this account yet.", bundle: #bundle),
                onSeeAll: detail.latestTransactions.isEmpty ? nil : { onSeeAllMovements(detail.account.id) },
            ) { transaction in
                KWTransactionRow(
                    display.style(of: transaction),
                    title: transaction.description,
                    subtitle: display.subtitle(of: transaction),
                    amount: display.amount(of: transaction),
                    secondaryAmount: display.secondaryAmount(of: transaction),
                )
            }
        }
    }
}
