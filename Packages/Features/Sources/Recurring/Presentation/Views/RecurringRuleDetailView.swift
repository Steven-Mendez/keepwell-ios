import Core
import DesignSystem
import Domain
import DomainSamples
import RecurringDomain
import SharedPresentation
import SwiftUI

/// A recurring rule read, not edited: whether this cycle is paid, when the next payment is and every
/// movement that paid it. "Link a payment" ties a movement recorded by hand to the rule; swiping a
/// payment left takes it out again. "Edit" opens the rule's form.
public struct RecurringRuleDetailView: View {
    @Bindable private var viewModel: RecurringRuleDetailViewModel
    private let onBack: () -> Void
    private let onEdit: () -> Void
    private let onOpenTransaction: (UUID) -> Void
    @State private var isLinking = false

    public init(
        viewModel: RecurringRuleDetailViewModel,
        onBack: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onOpenTransaction: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onEdit = onEdit
        self.onOpenTransaction = onOpenTransaction
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                header
                if viewModel.state == .failed {
                    Text("We couldn't load your recurring movements.", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                } else if let rule = viewModel.rule {
                    summary(rule)
                    statusCard
                    if let error = viewModel.actionError {
                        Text(error)
                            .font(KWTextStyle.caption.font)
                            .foregroundStyle(KWColor.State.negative)
                    }
                    payments
                    nextDates
                    Button {
                        Task { await viewModel.togglePaused() }
                    } label: {
                        rule.isPaused ? Text("Resume", bundle: #bundle) : Text("Pause", bundle: #bundle)
                    }
                    .buttonStyle(.kw(.surface, size: .row))
                    .disabled(viewModel.isWorking)
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        // Deleted from its editor, or on another device: there is nothing left to show.
        .onChange(of: viewModel.state == .missing) { _, missing in
            if missing {
                onBack()
            }
        }
        .sheet(isPresented: $isLinking) {
            RecurringLinkPaymentSheet(viewModel: viewModel) { isLinking = false }
                .presentationDetents([.medium, .large])
                .presentationBackground(KWColor.Surface.bg)
        }
    }

    private var header: some View {
        HStack(spacing: KWSpacing.sm) {
            KWNavigationHeader(viewModel.rule?.name ?? "", style: .large, onBack: onBack)
            KWCircleButton(.pencil, accessibilityLabel: String(localized: "Edit", bundle: #bundle), action: onEdit)
        }
    }

    private func summary(_ rule: RecurringRule) -> some View {
        VStack(spacing: KWSpacing.xxs) {
            icon(rule)
            Text(viewModel.amount)
                .font(.kw(26, weight: 800, relativeTo: .title2))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(amountColor(rule))
                .padding(.top, KWSpacing.xs)
            Text(viewModel.schedule)
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The state in a capsule (green once paid, amber while something waits), the next payment
    /// under it, and "Confirm" beside them while a draft waits.
    private var statusCard: some View {
        HStack(alignment: .center, spacing: KWSpacing.sm) {
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                Text(viewModel.stateLabel)
                    .font(KWTextStyle.caption.font.weight(.bold))
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, KWSpacing.xs)
                    .padding(.vertical, 4)
                    .background(stateColor.opacity(0.16), in: Capsule())
                if let next = viewModel.nextPayment {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("Next payment", bundle: #bundle).foregroundStyle(KWColor.Text.muted)
                        Text(verbatim: " · \(next)")
                    }
                    .font(.kw(15, weight: 600))
                    .accessibilityElement(children: .combine)
                }
                if let last = viewModel.lastPayment {
                    Text(last)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let draft = viewModel.status?.draft {
                Button {
                    Task { await viewModel.confirm() }
                } label: {
                    Text("Confirm", bundle: #bundle)
                }
                .buttonStyle(.kw(.primary, size: .mini))
                .disabled(viewModel.isWorking)
                .accessibilityLabel(Text("Confirm \(draft.description)", bundle: #bundle))
            }
        }
        .padding(KWSpacing.md)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    @ViewBuilder
    private var payments: some View {
        KWSectionHeader(String(localized: "Payments", bundle: #bundle)) {
            Button { isLinking = true } label: {
                Text("Link a payment", bundle: #bundle)
                    .font(KWTextStyle.label.font)
                    .foregroundStyle(KWColor.Brand.link)
                    .frame(minHeight: KWLayout.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if let history = viewModel.history, let display = viewModel.display, !history.payments.isEmpty {
            KWGroupedCard {
                KWValueRow(
                    String(localized: "Paid this year", bundle: #bundle),
                    value: "\(viewModel.paidThisYear) · \(viewModel.paymentsCount)",
                )
                if let change = viewModel.priceChange {
                    Text(change)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.pending)
                        .padding(.bottom, KWSpacing.sm)
                }
            }
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                ForEach(history.payments) { transaction in
                    paymentRow(transaction, display: display)
                }
            }
        } else {
            KWGroupedCard(verticalPadding: KWSpacing.sm) {
                KWTitleSubtitle(
                    String(localized: "No payments yet", bundle: #bundle),
                    subtitle: String(
                        localized: "Link a movement you already recorded and it counts as a payment of this one.",
                        bundle: #bundle,
                    ),
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A payment opens its movement; swiping it left takes it out of the rule. A draft is the rule's
    /// own occurrence waiting, so it can't be unlinked.
    private func paymentRow(_ transaction: Domain.Transaction, display: TransactionDisplay) -> some View {
        Button { onOpenTransaction(transaction.id) } label: {
            KWTransactionRow(
                display.style(of: transaction),
                title: transaction.description,
                subtitle: viewModel.subtitle(of: transaction),
                amount: display.amount(of: transaction),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kwSwipeAction(
            .close,
            tint: KWColor.State.negative,
            label: Text("Unlink payment", bundle: #bundle),
            isEnabled: transaction.isConfirmed,
        ) {
            Task { await viewModel.unlink(transaction.id) }
        }
    }

    @ViewBuilder
    private var nextDates: some View {
        if !viewModel.nextDates.isEmpty {
            KWSectionHeader(String(localized: "Next dates", bundle: #bundle))
            KWGroupedCard {
                ForEach(Array(viewModel.nextDates.enumerated()), id: \.offset) { _, day in
                    KWValueRow(day, value: "", style: .setting)
                }
            }
        }
    }

    private var stateColor: Color {
        switch viewModel.status?.state {
        case .paid: KWColor.State.positive
        case .overdue, .toConfirm: KWColor.State.pending
        default: KWColor.Text.secondary
        }
    }

    @ViewBuilder
    private func icon(_ rule: RecurringRule) -> some View {
        if rule.kind == .transfer {
            KWTransactionIcon(.transfer)
        } else {
            let category = viewModel.category
            BrandOrFallbackIcon(text: rule.name, tint: CategoryDisplay.color(for: category)) {
                CategorySymbol(category, size: 18)
                    .foregroundStyle(CategoryDisplay.color(for: category))
                    .frame(width: 40, height: 40)
                    .background(CategoryDisplay.color(for: category).opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
            }
        }
    }

    private func amountColor(_ rule: RecurringRule) -> Color {
        switch rule.kind {
        case .expense: KWTransactionStyle.expense.amountColor
        case .income: KWTransactionStyle.income.amountColor
        case .transfer: KWTransactionStyle.transfer.amountColor
        }
    }
}

/// "Link a payment": movements already recorded that could be this rule's payment. The suggested
/// ones match its amount or its name; the rest are found by searching.
struct RecurringLinkPaymentSheet: View {
    @Bindable var viewModel: RecurringRuleDetailViewModel
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                Text("Link a payment", bundle: #bundle)
                    .font(.kw(20, weight: 700, relativeTo: .title3))
                TextField(text: $viewModel.query) {
                    Text("Search movements", bundle: #bundle)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, KWSpacing.md)
                .frame(minHeight: KWLayout.minTouch)
                .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
                if let error = viewModel.actionError {
                    Text(error)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
                list(String(localized: "Suggested", bundle: #bundle), viewModel.suggested)
                list(String(localized: "Other movements", bundle: #bundle), viewModel.others)
                if viewModel.suggested.isEmpty, viewModel.others.isEmpty {
                    Text("No movements to link", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                }
            }
            .padding(KWLayout.gutter)
            .padding(.top, KWSpacing.sm)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(KWColor.Text.primary)
    }

    @ViewBuilder
    private func list(_ title: String, _ transactions: [Domain.Transaction]) -> some View {
        if let display = viewModel.display, !transactions.isEmpty {
            KWSectionHeader(title)
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                ForEach(transactions) { transaction in
                    Button {
                        Task {
                            if await viewModel.link(transaction.id) {
                                onDone()
                            }
                        }
                    } label: {
                        KWTransactionRow(
                            display.style(of: transaction),
                            title: transaction.description,
                            subtitle: viewModel.subtitle(of: transaction),
                            amount: display.amount(of: transaction),
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isWorking)
                }
            }
        }
    }
}

#Preview {
    RecurringRuleDetailView(
        viewModel: RecurringPreview.detailViewModel(ruleID: SampleData.IDs.streamingRule),
        onBack: {},
        onEdit: {},
        onOpenTransaction: { _ in },
    )
}
