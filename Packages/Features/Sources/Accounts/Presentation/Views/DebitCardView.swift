import AccountsDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// A bank account and its card as one screen, laid out like a bank's "my card" screen: the card,
/// the account's name and balance (with an eye to hide it), round quick actions, the list to
/// manage both, the latest movements and, set apart at the end, deleting the account.
public struct DebitCardView: View {
    private let viewModel: DebitCardViewModel
    private let onBack: () -> Void
    private let onSeeAllMovements: (UUID) -> Void
    @State private var sheet: Sheet?
    @State private var isConfirmingDeletion = false

    enum Sheet: String, Identifiable {
        case name
        case color
        case details
        var id: String { rawValue }
    }

    /// `onSeeAllMovements` opens the movement list filtered to the account it receives.
    public init(
        viewModel: DebitCardViewModel,
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
                KWNavigationHeader(String(localized: "Bank account", bundle: #bundle), buttonStyle: .translucent, onBack: onBack)
                if let detail = viewModel.detail {
                    CardHero(art: art(detail), name: detail.account.name, subtitle: viewModel.subtitle(detail))
                    BalanceHeader(String(localized: "Available balance", bundle: #bundle), amount: viewModel.balance(detail))
                        .padding(.top, -KWSpacing.sm)
                    actions(detail)
                    manage(detail)
                    latest(detail)
                    deleteButton
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
        .sheet(item: $sheet, onDismiss: viewModel.clearError) { sheet in
            Group {
                if let detail = viewModel.detail {
                    switch sheet {
                    case .name:
                        CardNameSheet(
                            name: detail.account.name,
                            errorMessage: viewModel.errorMessage,
                            isSaving: viewModel.isSaving,
                            onSave: viewModel.rename(to:),
                            onClose: { self.sheet = nil },
                        )
                    case .color:
                        CardColorSheet(
                            color: detail.card.color,
                            preview: { color in
                                CardDisplay.art(
                                    of: detail.card.with(color: color),
                                    kind: .debit,
                                    bank: viewModel.bank(detail),
                                    ownerName: viewModel.ownerName,
                                    caption: caption(detail),
                                )
                            },
                            onSave: viewModel.setColor,
                            onClose: { self.sheet = nil },
                        )
                    case .details:
                        CardDetailsSheet(
                            card: detail.card,
                            errorMessage: viewModel.errorMessage,
                            isSaving: viewModel.isSaving,
                            onSave: viewModel.setDetails,
                            onClose: { self.sheet = nil },
                        )
                    }
                }
            }
            .presentationDetents([.large])
            .presentationBackground(KWColor.Surface.bg)
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
        } message: {
            if let detail = viewModel.detail {
                Text(viewModel.deleteMessage(detail))
            }
        }
    }

    /// The card's color bleeds into the top of the screen, so each card's page feels like its own.
    private var glow: some View {
        let palette = CardDisplay.palette(for: viewModel.detail?.card.color)
        return LinearGradient(colors: [Color(hex: palette.hexStops.end).opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
            .frame(height: 460)
            .animation(.snappy, value: viewModel.detail?.card)
    }

    private func art(_ detail: DebitCardDetail) -> KWCardArt {
        // The balance reads under the name, so the card face stays a card.
        CardDisplay.art(
            of: detail.card,
            kind: .debit,
            bank: viewModel.bank(detail),
            ownerName: viewModel.ownerName,
            caption: caption(detail),
        )
    }

    private func caption(_ detail: DebitCardDetail) -> String? {
        detail.account.bank == nil ? nil : detail.account.name
    }

    private func actions(_ detail: DebitCardDetail) -> some View {
        VStack(spacing: KWSpacing.sm) {
            HStack(spacing: KWSpacing.xs) {
                KWActionButton(String(localized: "Edit name", bundle: #bundle), icon: .pencil) { sheet = .name }
                KWActionButton(String(localized: "Color", bundle: #bundle), icon: .droplet) { sheet = .color }
            }
            .frame(maxWidth: KWComponentMetrics.actionPairWidth)
            if let error = viewModel.errorMessage, sheet == nil {
                Text(error)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.State.negative)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func manage(_ detail: DebitCardDetail) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            KWSectionHeader(String(localized: "Manage account", bundle: #bundle), style: .large)
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                CardManageRow(String(localized: "Edit name", bundle: #bundle), icon: .pencil, value: detail.account.name) {
                    sheet = .name
                }
                CardManageRow(
                    String(localized: "Card color", bundle: #bundle),
                    icon: .droplet,
                    value: CardDisplay.palette(for: detail.card.color).displayName,
                ) {
                    sheet = .color
                }
                CardManageRow(
                    String(localized: "Product and expiry", bundle: #bundle),
                    icon: .creditCard,
                    value: CardDisplay.detailsSummary(of: detail.card),
                ) {
                    sheet = .details
                }
            }
        }
    }
}

extension DebitCardView {
    /// Apart from the edits, Revolut-style, so it isn't tapped on the way to "Card color".
    private var deleteButton: some View {
        KWGroupedCard(verticalPadding: KWSpacing.xxs) {
            CardManageRow(String(localized: "Delete account", bundle: #bundle), icon: .trash, isDestructive: true) {
                isConfirmingDeletion = true
            }
        }
    }

    @ViewBuilder
    private func latest(_ detail: DebitCardDetail) -> some View {
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

#Preview {
    DebitCardPreview()
}

private struct DebitCardPreview: View {
    @State private var viewModel = AccountsPreviewData.debitCardViewModel()

    var body: some View {
        DebitCardView(viewModel: viewModel, onBack: {}, onSeeAllMovements: { _ in })
            .onAppear { KWFonts.register() }
    }
}
