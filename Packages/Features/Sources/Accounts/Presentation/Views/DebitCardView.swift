import AccountsDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// One debit card, laid out like a bank's "my card" screen: the card, the account's name and
/// balance (with an eye to hide it), round quick actions, the list to manage it and the account's
/// latest movements.
public struct DebitCardView: View {
    private let viewModel: DebitCardViewModel
    private let onBack: () -> Void
    private let onLinkCard: (UUID) -> Void
    private let onSeeAllMovements: (UUID) -> Void
    @State private var sheet: Sheet?
    @State private var isConfirmingRemoval = false

    enum Sheet: String, Identifiable {
        case name
        case color
        var id: String { rawValue }
    }

    /// `onSeeAllMovements` opens the movement list filtered to the account it receives.
    public init(
        viewModel: DebitCardViewModel,
        onBack: @escaping () -> Void,
        onLinkCard: @escaping (UUID) -> Void,
        onSeeAllMovements: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onLinkCard = onLinkCard
        self.onSeeAllMovements = onSeeAllMovements
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.lg) {
                KWNavigationHeader(String(localized: "Debit card", bundle: #bundle), buttonStyle: .translucent, onBack: onBack)
                if let detail = viewModel.detail {
                    CardHero(art: art(detail), name: detail.account.name, subtitle: viewModel.subtitle(detail))
                    BalanceHeader(String(localized: "Available balance", bundle: #bundle), amount: viewModel.balance(detail))
                        .padding(.top, -KWSpacing.sm)
                    actions(detail)
                    manage(detail)
                    latest(detail)
                } else if viewModel.state == .failed {
                    Text("We couldn't load this card.", bundle: #bundle)
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
                                    caption: caption(detail),
                                )
                            },
                            onSave: viewModel.setColor,
                            onClose: { self.sheet = nil },
                        )
                    }
                }
            }
            .presentationDetents([.large])
            .presentationBackground(KWColor.Surface.bg)
        }
        .confirmationDialog(
            String(localized: "Remove this card?", bundle: #bundle),
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task {
                    if await viewModel.remove() {
                        onBack()
                    }
                }
            } label: {
                Text("Remove card", bundle: #bundle)
            }
        } message: {
            Text("Its past movements stay on the account.", bundle: #bundle)
        }
    }

    /// The card's color bleeds into the top of the screen, so each card's page feels like its own.
    private var glow: some View {
        let palette = CardDisplay.palette(for: viewModel.detail?.card.color)
        let tint = viewModel.detail?.card.isFrozen == true ? KWColor.Surface.surface2 : Color(hex: palette.hexStops.end)
        return LinearGradient(colors: [tint.opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
            .frame(height: 460)
            .animation(.snappy, value: viewModel.detail?.card)
    }

    private func art(_ detail: DebitCardDetail) -> KWCardArt {
        // The balance reads under the name, so the card face stays a card.
        CardDisplay.art(
            of: detail.card,
            kind: .debit,
            bank: viewModel.bank(detail),
            badge: detail.card.isFrozen ? .tag(String(localized: "Frozen", bundle: #bundle)) : nil,
            caption: caption(detail),
        )
    }

    private func caption(_ detail: DebitCardDetail) -> String? {
        detail.account.bank == nil ? nil : detail.account.name
    }

    private func actions(_ detail: DebitCardDetail) -> some View {
        let isFrozen = detail.card.isFrozen
        return VStack(spacing: KWSpacing.sm) {
            HStack(spacing: KWSpacing.xs) {
                KWActionButton(String(localized: "Edit name", bundle: #bundle), icon: .pencil) { sheet = .name }
                KWActionButton(String(localized: "Color", bundle: #bundle), icon: .droplet) { sheet = .color }
                KWActionButton(
                    isFrozen ? String(localized: "Unfreeze", bundle: #bundle) : String(localized: "Freeze", bundle: #bundle),
                    icon: .freeze,
                    style: isFrozen ? .active : .neutral,
                ) {
                    Task { await viewModel.toggleFrozen() }
                }
            }
            if isFrozen {
                Text("A frozen card can't be picked to pay a movement.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if let error = viewModel.errorMessage, sheet == nil {
                Text(error)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.State.negative)
            }
        }
        .animation(.snappy, value: isFrozen)
    }

    private func manage(_ detail: DebitCardDetail) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            KWSectionHeader(String(localized: "Manage card", bundle: #bundle), style: .large)
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
                CardManageRow(String(localized: "Link another card", bundle: #bundle), icon: .addCard) {
                    onLinkCard(detail.account.id)
                }
                CardManageRow(String(localized: "Remove card", bundle: #bundle), icon: .trash, isDestructive: true) {
                    isConfirmingRemoval = true
                }
            }
        }
    }
}

extension DebitCardView {
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
        DebitCardView(viewModel: viewModel, onBack: {}, onLinkCard: { _ in }, onSeeAllMovements: { _ in })
            .onAppear { KWFonts.register() }
    }
}
