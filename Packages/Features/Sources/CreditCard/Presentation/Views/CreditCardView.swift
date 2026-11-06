import CreditCardDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// A credit card: its art, what's owed per currency, billing data and this cycle.
public struct CreditCardView: View {
    private let viewModel: CreditCardViewModel
    private let onBack: () -> Void
    private let onPay: () -> Void
    private let onSeeAllMovements: () -> Void
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case terms
        case name
        case color
        var id: String { rawValue }
    }

    /// `onSeeAllMovements` opens the card's whole history, past cycles included.
    public init(
        viewModel: CreditCardViewModel,
        onBack: @escaping () -> Void,
        onPay: @escaping () -> Void,
        onSeeAllMovements: @escaping () -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onPay = onPay
        self.onSeeAllMovements = onSeeAllMovements
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                if let detail = viewModel.detail {
                    KWNavigationHeader(String(localized: "Credit card", bundle: #bundle), buttonStyle: .translucent, onBack: onBack)
                    CardHero(art: art(detail), name: detail.account.name)
                    debt(detail)
                    actions
                    terms(detail)
                    manage(detail)
                    cycle(detail)
                } else {
                    KWNavigationHeader("", buttonStyle: .translucent, onBack: onBack)
                    if viewModel.state == .failed {
                        Text("We couldn't load this card.", bundle: #bundle)
                            .foregroundStyle(KWColor.Text.muted)
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, 28)
            // Scrolls with the card, as in the design, fading to black under the debt.
            .background(alignment: .top) {
                LinearGradient(colors: [KWColor.Brand.b900, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 420)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(item: $sheet, onDismiss: viewModel.clearError) { sheet in
            Group {
                switch sheet {
                case .terms:
                    if let detail = viewModel.detail {
                        TermsSheet(viewModel: viewModel, detail: detail) { self.sheet = nil }
                    }
                case .name:
                    if let detail = viewModel.detail {
                        CardNameSheet(
                            name: detail.account.name,
                            errorMessage: viewModel.errorMessage,
                            isSaving: viewModel.isSaving,
                            onSave: viewModel.rename(to:),
                            onClose: { self.sheet = nil },
                        )
                    }
                case .color:
                    if let detail = viewModel.detail, let holder = detail.holder {
                        CardColorSheet(
                            color: holder.color,
                            preview: { color in colorPreview(holder.with(color: color), detail) },
                            onSave: viewModel.setHolderColor,
                            onClose: { self.sheet = nil },
                        )
                    }
                }
            }
            .presentationDetents([.large])
            .presentationBackground(KWColor.Surface.bg)
        }
    }

    private func art(_ detail: CreditCardDetail) -> KWCardArt {
        CardDisplay.art(
            of: detail.holder,
            kind: .creditHolder,
            bank: viewModel.bank(detail),
            ownerName: viewModel.ownerName,
            caption: detail.account.bank == nil ? nil : detail.account.name,
        )
    }

    private func colorPreview(_ holder: Card, _ detail: CreditCardDetail) -> KWCardArt {
        CardDisplay.art(of: holder, kind: .creditHolder, bank: viewModel.bank(detail), ownerName: viewModel.ownerName)
    }

    private func debt(_ detail: CreditCardDetail) -> some View {
        BalanceHeader(
            String(localized: "Current debt", bundle: #bundle),
            amount: viewModel.owed(detail.totalDebt),
            details: detail.balances.count > 1 ? viewModel.debtsSecondFirst(detail).map(viewModel.owed) : [],
        )
    }

    @ViewBuilder
    private func cycle(_ detail: CreditCardDetail) -> some View {
        if let display = viewModel.display {
            LatestMovementsSection(
                String(localized: "This cycle", bundle: #bundle),
                transactions: detail.cycleTransactions,
                emptyMessage: String(localized: "Nothing charged this cycle yet.", bundle: #bundle),
                onSeeAll: onSeeAllMovements,
            ) { transaction in
                cycleRow(transaction, display: display, detail: detail)
            }
            .padding(.top, KWSpacing.xxs)
        }
    }

    private func cycleRow(_ transaction: Domain.Transaction, display: TransactionDisplay, detail: CreditCardDetail) -> some View {
        // Everything here was charged to this one card, so the row names the category, not the card.
        let color = CardDisplay.palette(for: detail.holder?.color)
        let day = transaction.date.formatted(.dateTime.day().month(.abbreviated))
        let subtitle = [display.categoryName(of: transaction), day].compactMap(\.self).joined(separator: " · ")
        return HStack(spacing: KWSpacing.sm) {
            Capsule()
                .fill(color.gradient)
                .frame(width: 8, height: 28)
            KWTitleSubtitle(transaction.description, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(display.amount(of: transaction))
                .font(.kw(15, weight: 700))
                .monospacedDigit()
                .foregroundStyle(display.style(of: transaction).amountColor)
        }
        .padding(.vertical, KWSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Actions and billing data

extension CreditCardView {
    /// Two actions, kept close together under the card rather than pushed to the screen's edges.
    private var actions: some View {
        HStack(spacing: KWSpacing.xs) {
            KWActionButton(String(localized: "Pay", bundle: #bundle), icon: .arrowUp, style: .prominent, action: onPay)
            KWActionButton(String(localized: "Edit name", bundle: #bundle), icon: .pencil) { sheet = .name }
        }
        .frame(maxWidth: KWComponentMetrics.actionPairWidth)
        .frame(maxWidth: .infinity)
    }

    /// What can be changed about the card itself, LAFISE-style, after what it shows.
    private func manage(_ detail: CreditCardDetail) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            KWSectionHeader(String(localized: "Manage card", bundle: #bundle), style: .large)
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                CardManageRow(String(localized: "Edit name", bundle: #bundle), icon: .pencil, value: detail.account.name) {
                    sheet = .name
                }
                if let holder = detail.holder {
                    CardManageRow(
                        String(localized: "Card color", bundle: #bundle),
                        icon: .droplet,
                        value: CardDisplay.palette(for: holder.color).displayName,
                    ) {
                        sheet = .color
                    }
                }
                CardManageRow(String(localized: "Billing details", bundle: #bundle), icon: .creditCard) { sheet = .terms }
            }
        }
    }

    private func terms(_ detail: CreditCardDetail) -> some View {
        let terms = detail.account.creditTerms
        let notSet = String(localized: "Not set", bundle: #bundle)
        let isComplete = terms?.limit != nil && terms?.cutoffDay != nil && terms?.dueDay != nil
        return KWGroupedCard(verticalPadding: KWSpacing.xxs) {
            termRow(String(localized: "Credit limit", bundle: #bundle), terms?.limit.map { viewModel.money($0) }, notSet: notSet)
            termRow(String(localized: "Available", bundle: #bundle), detail.available.map { viewModel.money($0) }, notSet: "—")
            termRow(
                String(localized: "Cutoff date", bundle: #bundle),
                viewModel.dayOfMonth(terms?.cutoffDay, next: detail.nextCutoff),
                notSet: notSet,
            )
            termRow(
                String(localized: "Payment date", bundle: #bundle),
                viewModel.dayOfMonth(terms?.dueDay, next: detail.nextDue),
                notSet: notSet,
            )
            if !isComplete {
                Button { sheet = .terms } label: {
                    Text("Complete card details", bundle: #bundle)
                }
                .buttonStyle(.kw(.link, size: .medium))
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
        }
    }

    private func termRow(_ label: String, _ value: String?, notSet: String) -> some View {
        KWValueRow(label, value: value ?? notSet, style: value == nil ? .placeholder : .detail)
    }
}
