import CreditCardDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// A credit card: its art, what's owed per currency, billing data, plastics and this cycle.
public struct CreditCardView: View {
    private let viewModel: CreditCardViewModel
    private let onBack: () -> Void
    private let onPay: () -> Void
    private let onOpenAdditional: (UUID) -> Void
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case terms
        case newAdditional
        case name
        case color
        var id: String { rawValue }
    }

    /// `startsAddingAdditional` opens the new-additional form right away (from "Card added").
    public init(
        viewModel: CreditCardViewModel,
        startsAddingAdditional: Bool = false,
        onBack: @escaping () -> Void,
        onPay: @escaping () -> Void,
        onOpenAdditional: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onPay = onPay
        self.onOpenAdditional = onOpenAdditional
        _sheet = State(initialValue: startsAddingAdditional ? .newAdditional : nil)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                if let detail = viewModel.detail {
                    KWNavigationHeader(String(localized: "Credit card", bundle: #bundle), buttonStyle: .translucent, onBack: onBack)
                    CardHero(art: art(detail), name: detail.account.name)
                        .animation(.snappy, value: isHolderFrozen)
                    debt(detail)
                    actions
                    terms(detail)
                    plastics(detail)
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
                            preview: { color in
                                CardDisplay.art(of: holder.with(color: color), kind: .creditHolder, bank: viewModel.bank(detail))
                            },
                            onSave: viewModel.setHolderColor,
                            onClose: { self.sheet = nil },
                        )
                    }
                case .newAdditional:
                    NewAdditionalSheet(viewModel: viewModel) { cardID in
                        self.sheet = nil
                        if let cardID {
                            onOpenAdditional(cardID)
                        }
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
            badge: .tag(isHolderFrozen ? String(localized: "Frozen", bundle: #bundle) : String(localized: "Holder", bundle: #bundle)),
            caption: detail.account.bank == nil ? nil : detail.account.name,
        )
    }

    private var isHolderFrozen: Bool {
        viewModel.detail?.holder?.isFrozen == true
    }

    private func debt(_ detail: CreditCardDetail) -> some View {
        VStack(spacing: KWSpacing.xxs) {
            Text("Current debt", bundle: #bundle)
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.onBrand)
            Text(viewModel.owed(detail.totalDebt))
                .kwTextStyle(.amountLg)
                .tracking(-1.2)
            if detail.balances.count > 1 {
                HStack(spacing: 6) {
                    ForEach(viewModel.debtsSecondFirst(detail), id: \.currency) { balance in
                        Text(viewModel.owed(balance))
                            .font(.kw(13, weight: 600, relativeTo: .footnote))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(KWColor.Overlay.white14, in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func plastics(_ detail: CreditCardDetail) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSectionHeader(String(localized: "Plastics", bundle: #bundle), style: .large) {
                Button { sheet = .newAdditional } label: {
                    Text("+ Additional", bundle: #bundle)
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Brand.link)
                        .frame(minHeight: KWLayout.minTouch)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, -KWSpacing.sm)
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                HStack(spacing: KWSpacing.sm) {
                    KWMiniCard(.palette(CardDisplay.palette(for: detail.holder?.color), chip: true))
                    KWTitleSubtitle(viewModel.holderTitle(detail), subtitle: String(localized: "You · no cap", bundle: #bundle))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(Array(viewModel.debtsSecondFirst(detail).enumerated()), id: \.offset) { index, balance in
                            Text(index == 0 ? viewModel.owed(balance) : "+ \(viewModel.owed(balance))")
                                .font(index == 0 ? .kw(15, weight: 700) : KWTextStyle.captionSm.font.weight(.regular))
                                .foregroundStyle(index == 0 ? KWColor.Text.primary : KWColor.Text.muted)
                        }
                    }
                    .monospacedDigit()
                }
                .padding(.vertical, 14)
                ForEach(detail.additionals) { additional in
                    Button { onOpenAdditional(additional.id) } label: {
                        additionalRow(additional, detail: detail)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func additionalRow(_ additional: CreditCardDetail.Additional, detail: CreditCardDetail) -> some View {
        let card = additional.card
        let isFrozen = card.additional?.isFrozen == true
        return VStack(spacing: 10) {
            HStack(spacing: KWSpacing.sm) {
                KWMiniCard(isFrozen ? .palette(.grafito, chip: true) : .palette(CardDisplay.palette(for: card.color), chip: true))
                KWTitleSubtitle(
                    card.additional?.holderName ?? String(localized: "Additional", bundle: #bundle),
                    subtitle: viewModel.additionalSubtitle(card, categories: detail.categories),
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.money(additional.usage.spent, fractionDigits: 0)).font(.kw(15, weight: 700))
                    if let cap = additional.usage.cap {
                        Text("of \(viewModel.money(cap, fractionDigits: 0))", bundle: #bundle)
                            .font(KWTextStyle.captionSm.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                    }
                }
                .monospacedDigit()
            }
            if let fraction = additional.usage.fraction {
                KWProgressBar(
                    fraction.doubleValue,
                    fill: fraction >= detail.capAlertThreshold ? KWColor.State.pending : KWColor.State.extra,
                )
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cycle(_ detail: CreditCardDetail) -> some View {
        if let display = viewModel.display, !detail.cycleTransactions.isEmpty {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWSectionHeader(String(localized: "This cycle", bundle: #bundle), style: .large)
                    .padding(.top, KWSpacing.xxs)
                KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                    ForEach(detail.cycleTransactions) { transaction in
                        cycleRow(transaction, display: display, detail: detail)
                    }
                }
            }
        }
    }

    private func cycleRow(_ transaction: Domain.Transaction, display: TransactionDisplay, detail: CreditCardDetail) -> some View {
        let card = transaction.cardID.flatMap { id in detail.cards.first { $0.id == id } }
        let color = card.map { CardDisplay.palette(for: $0.color) } ?? CardDisplay.palette(for: detail.holder?.color)
        let who = card.map { CardDisplay.methodTitle($0, account: detail.account) } ?? String(localized: "Holder", bundle: #bundle)
        let day = transaction.date.formatted(.dateTime.day().month(.abbreviated))
        let subtitle = [who, display.categoryName(of: transaction), day].compactMap(\.self).joined(separator: " · ")
        return HStack(spacing: KWSpacing.sm) {
            Capsule()
                .fill(color.gradient)
                .frame(width: 8, height: 28)
            KWTitleSubtitle(transaction.description, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(display.amount(of: transaction))
                .font(.kw(15, weight: 700))
                .monospacedDigit()
                .foregroundStyle(transaction.isConfirmed ? KWColor.Text.primary : KWColor.State.pending)
        }
        .padding(.vertical, KWSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Actions and billing data

extension CreditCardView {
    private var actions: some View {
        HStack(spacing: KWSpacing.xs) {
            KWActionButton(String(localized: "Pay", bundle: #bundle), icon: .arrowUp, style: .prominent, action: onPay)
            if viewModel.detail?.holder != nil {
                KWActionButton(
                    isHolderFrozen ? String(localized: "Unfreeze", bundle: #bundle) : String(localized: "Freeze", bundle: #bundle),
                    icon: .freeze,
                    style: isHolderFrozen ? .active : .neutral,
                ) {
                    Task { await viewModel.setHolderFrozen(!isHolderFrozen) }
                }
            }
            KWActionButton(String(localized: "Edit name", bundle: #bundle), icon: .pencil) { sheet = .name }
            KWActionButton(String(localized: "Additional", bundle: #bundle), icon: .addCard) { sheet = .newAdditional }
        }
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
                CardManageRow(String(localized: "New additional card", bundle: #bundle), icon: .addCard) { sheet = .newAdditional }
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
