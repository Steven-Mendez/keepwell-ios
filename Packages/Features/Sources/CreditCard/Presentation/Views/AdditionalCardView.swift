import CreditCardDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Controls the holder sets on an additional card: freeze it, cap it per cycle, choose where it
/// can be used, alerts, the category its purchases default to, and removing it.
public struct AdditionalCardView: View {
    private let viewModel: CreditCardViewModel
    private let cardID: UUID
    private let onBack: () -> Void
    @State private var isEditingCap = false
    @State private var isConfirmingRemoval = false

    public init(viewModel: CreditCardViewModel, cardID: UUID, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.cardID = cardID
        self.onBack = onBack
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: KWSpacing.md) {
                    if let detail = viewModel.detail, let additional = detail.additional(id: cardID),
                       let controls = additional.card.additional
                    {
                        KWNavigationHeader(
                            controls.holderName,
                            subtitle: String(localized: "Additional of \(viewModel.title(detail))", bundle: #bundle),
                            style: .leading,
                            onBack: onBack,
                        )
                        art(additional.card, controls: controls, detail: detail)
                        actions(controls, proxy: proxy)
                        capCard(additional, detail: detail)
                        categories(controls)
                        alerts(controls, detail: detail)
                        defaultCategory(controls)
                        spending(detail)
                            .id("spending")
                        SheetError(message: viewModel.errorMessage)
                        Button { isConfirmingRemoval = true } label: {
                            Text("Remove additional", bundle: #bundle)
                        }
                        .buttonStyle(.kw(.destructive, size: .row))
                        .disabled(viewModel.isSaving)
                    } else {
                        KWNavigationHeader("", style: .leading, onBack: onBack)
                    }
                }
                .padding(.horizontal, KWLayout.gutter)
                .padding(.top, KWLayout.safeTop)
                .padding(.bottom, 28)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(isPresented: $isEditingCap, onDismiss: viewModel.clearError) {
            CapSheet(viewModel: viewModel, cardID: cardID) { isEditingCap = false }
                .presentationDetents([.medium])
                .presentationBackground(KWColor.Surface.bg)
        }
        .confirmationDialog(
            String(localized: "Remove this additional card?", bundle: #bundle),
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task {
                    if await viewModel.remove(cardID) {
                        onBack()
                    }
                }
            } label: {
                Text("Remove", bundle: #bundle)
            }
        } message: {
            Text("Its past purchases stay on the card.", bundle: #bundle)
        }
    }

    private func art(_ card: Card, controls: AdditionalCardControls, detail: CreditCardDetail) -> some View {
        KWCardArt(
            palette: CardDisplay.palette(for: card.color ?? .lima),
            bank: viewModel.bank(detail),
            badge: .tag(controls.isFrozen ? String(localized: "Frozen", bundle: #bundle) : String(
                localized: "Additional",
                bundle: #bundle,
            )),
            caption: controls.holderName,
            lastFour: card.lastFour,
            network: CardDisplay.wordmark(for: card.network),
            isFrozen: controls.isFrozen,
        )
        .animation(.snappy, value: controls.isFrozen)
    }

    private func actions(_ controls: AdditionalCardControls, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: KWSpacing.xs) {
            KWActionButton(
                controls.isFrozen ? String(localized: "Unfreeze", bundle: #bundle) : String(localized: "Freeze", bundle: #bundle),
                icon: .freeze,
                style: controls.isFrozen ? .active : .neutral,
            ) {
                Task { await viewModel.setFrozen(cardID, !controls.isFrozen) }
            }
            KWActionButton(String(localized: "Its spending", bundle: #bundle), icon: .barsBaseline) {
                withAnimation { proxy.scrollTo("spending", anchor: .top) }
            }
            KWActionButton(String(localized: "Holder", bundle: #bundle), icon: .person, action: onBack)
        }
    }

    private func capCard(_ additional: CreditCardDetail.Additional, detail: CreditCardDetail) -> some View {
        let usage = additional.usage
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cap per cycle", bundle: #bundle).font(.kw(15, weight: 600))
                Spacer()
                Button { isEditingCap = true } label: {
                    Text("Edit", bundle: #bundle)
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Brand.link)
                        .frame(minWidth: KWLayout.minTouch, minHeight: KWLayout.minTouch, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .padding(.vertical, -KWSpacing.sm)
            }
            (Text(viewModel.money(usage.spent, fractionDigits: 0)).font(.kw(26, weight: 800, relativeTo: .title2))
                + Text(usage.cap.map { " " + String(localized: "of \(viewModel.money($0, fractionDigits: 0))", bundle: #bundle) } ?? "")
                .font(.kw(15, weight: 600))
                .foregroundColor(KWColor.Text.muted))
                .monospacedDigit()
            if let fraction = usage.fraction {
                KWProgressBar(
                    fraction.doubleValue,
                    fill: fraction >= detail.capAlertThreshold ? KWColor.State.pending : KWColor.State.extra,
                    height: 8,
                )
            }
            Text(viewModel.usageCaption(usage))
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    private func categories(_ controls: AdditionalCardControls) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSectionHeader(String(localized: "Where it can be used", bundle: #bundle), style: .large)
                .padding(.top, KWSpacing.xxs)
            KWFlowLayout(spacing: KWSpacing.xs) {
                ForEach(viewModel.expenseCategories) { category in
                    KWChip(
                        CategoryDisplay.name(of: category),
                        isSelected: viewModel.isAllowed(category.id, controls: controls),
                        style: .extra,
                    ) {
                        Task { await viewModel.toggleCategory(cardID, category.id) }
                    }
                }
            }
        }
    }

    private func alerts(_ controls: AdditionalCardControls, detail: CreditCardDetail) -> some View {
        let threshold = viewModel.thresholdPercent(detail)
        return VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSectionHeader(String(localized: "Alerts", bundle: #bundle), style: .large)
                .padding(.top, KWSpacing.xxs)
            KWGroupedCard {
                Toggle(isOn: Binding(
                    get: { controls.alertEachPurchase },
                    set: { isOn in Task { await viewModel.setAlertEachPurchase(cardID, isOn) } },
                )) {
                    Text("Each purchase", bundle: #bundle).font(KWTextStyle.body.font)
                }
                .toggleStyle(.kw)
                .padding(.vertical, 13)
                Toggle(isOn: Binding(
                    get: { controls.alertNearCap },
                    set: { isOn in Task { await viewModel.setAlertNearCap(cardID, isOn) } },
                )) {
                    Text("On reaching \(threshold) of the cap", bundle: #bundle).font(KWTextStyle.body.font)
                }
                .toggleStyle(.kw)
                .padding(.vertical, 13)
            }
        }
    }

    private func defaultCategory(_ controls: AdditionalCardControls) -> some View {
        let current = controls.defaultCategoryID.flatMap { id in viewModel.expenseCategories.first { $0.id == id } }
        return Menu {
            Button { Task { await viewModel.setDefaultCategory(cardID, nil) } } label: { Text("None", bundle: #bundle) }
            ForEach(viewModel.expenseCategories.filter { viewModel.isAllowed($0.id, controls: controls) }) { category in
                Button(CategoryDisplay.name(of: category)) { Task { await viewModel.setDefaultCategory(cardID, category.id) } }
            }
        } label: {
            HStack(spacing: KWSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log its purchases as", bundle: #bundle).font(KWTextStyle.body.font)
                    Text("Default category when logging", bundle: #bundle)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                }
                Spacer(minLength: KWSpacing.xs)
                Text(current.map(CategoryDisplay.name(of:)).map { "\($0) ›" } ?? String(localized: "None ›", bundle: #bundle))
                    .font(.kw(15, weight: 600))
            }
            .padding(.horizontal, KWSpacing.md)
            .padding(.vertical, 14)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func spending(_ detail: CreditCardDetail) -> some View {
        let purchases = detail.cycleTransactions.filter { $0.cardID == cardID }
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSectionHeader(String(localized: "Its purchases this cycle", bundle: #bundle), style: .large)
                .padding(.top, KWSpacing.xxs)
            if let display = viewModel.display, !purchases.isEmpty {
                KWGroupedCard(horizontalPadding: 14, verticalPadding: KWSpacing.xxs) {
                    ForEach(purchases) { transaction in
                        KWTransactionRow(
                            display.style(of: transaction),
                            title: transaction.description,
                            subtitle: [
                                display.categoryName(of: transaction),
                                transaction.date.formatted(.dateTime.day().month(.abbreviated)),
                            ]
                            .compactMap(\.self).joined(separator: " · "),
                            amount: display.amount(of: transaction),
                            secondaryAmount: display.secondaryAmount(of: transaction),
                        )
                    }
                }
            } else {
                Text("No purchases this cycle yet.", bundle: #bundle)
                    .font(KWTextStyle.body.font)
                    .foregroundStyle(KWColor.Text.muted)
            }
        }
    }
}

/// Edits an additional card's cap per cycle; empty removes it.
struct CapSheet: View {
    let viewModel: CreditCardViewModel
    let cardID: UUID
    let onClose: () -> Void
    @State private var capText: String

    init(viewModel: CreditCardViewModel, cardID: UUID, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.cardID = cardID
        self.onClose = onClose
        let cap = viewModel.detail?.additional(id: cardID)?.card.additional?.cycleCap
        _capText = State(initialValue: cap.map { viewModel.formatter.number($0.amount).replacingOccurrences(of: ",", with: "") } ?? "")
    }

    var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("Cap per cycle", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                KWGroupedCard {
                    SheetAmountField(
                        label: String(localized: "Amount (\(viewModel.detail?.capCurrency ?? ""))", bundle: #bundle),
                        placeholder: String(localized: "No cap", bundle: #bundle),
                        text: $capText,
                    )
                }
                Text("Leave it empty so the card has no cap. It restarts at each cutoff.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                SheetError(message: viewModel.errorMessage)
                Spacer(minLength: 0)
                Button {
                    KWKeyboard.dismiss()
                    Task {
                        if await viewModel.setCap(cardID, capText: capText) {
                            onClose()
                        }
                    }
                } label: {
                    Text("Save", bundle: #bundle)
                }
                .buttonStyle(.kw())
                .disabled(viewModel.isSaving)
            }
        }
    }
}
