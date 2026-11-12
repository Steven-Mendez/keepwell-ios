import DesignSystem
import Domain
import HomeDomain
import SharedPresentation
import SwiftUI

/// What's pending: everything overdue first, marked in the warning color and in words, then the
/// next few things due this week. Drafts are confirmed here; the rest open where they're paid.
struct HomeUpcomingCard: View {
    /// Where a row leads. Drafts have their own buttons instead.
    struct Actions {
        var openRule: (UUID) -> Void
        var openCard: (UUID) -> Void
        var debts: () -> Void
        var seeAll: () -> Void
    }

    let viewModel: HomeViewModel
    let rows: [UpcomingPayment]
    let hidesBalances: Bool
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Upcoming", bundle: #bundle)
                    .font(KWTextStyle.heading.font)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: actions.seeAll) {
                    Text("See all", bundle: #bundle)
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Brand.link)
                        .frame(minHeight: KWLayout.minTouch)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, -KWSpacing.sm)
            .padding(.bottom, KWSpacing.xxs)
            ForEach(rows) { payment in
                row(payment)
            }
            if let error = viewModel.actionError {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    @ViewBuilder
    private func row(_ payment: UpcomingPayment) -> some View {
        switch payment.kind {
        case let .draft(transaction):
            UpcomingPaymentRow(viewModel: viewModel, payment: payment) {
                KWTransactionIcon(.planned)
            } trailing: {
                draftButtons(transaction)
            }
        case let .recurring(rule):
            Button { actions.openRule(rule.id) } label: {
                UpcomingPaymentRow(viewModel: viewModel, payment: payment) {
                    // A known brand shows its logo; a transfer is never a merchant.
                    BrandOrFallbackIcon(
                        text: rule.kind == .transfer ? "" : rule.name,
                        tint: CategoryDisplay.color(for: viewModel.upcomingCategory(payment)),
                    ) {
                        KWTransactionIcon(style(of: payment))
                    }
                } trailing: {
                    amount(payment)
                }
            }
            .buttonStyle(.plain)
        case let .card(accountID, _):
            Button { actions.openCard(accountID) } label: {
                UpcomingPaymentRow(viewModel: viewModel, payment: payment) {
                    KWTransactionIcon(.planned)
                } trailing: {
                    amount(payment)
                }
            }
            .buttonStyle(.plain)
        case .installment, .debt:
            Button(action: actions.debts) {
                UpcomingPaymentRow(viewModel: viewModel, payment: payment) {
                    KWTransactionIcon(.planned)
                } trailing: {
                    amount(payment)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Income reads as income (D5); everything else as something still to pay.
    private func style(of payment: UpcomingPayment) -> KWTransactionStyle {
        if case let .recurring(rule) = payment.kind, rule.kind == .income {
            .income
        } else {
            .planned
        }
    }

    private func amount(_ payment: UpcomingPayment) -> some View {
        KWTransactionAmounts(style(of: payment), amount: viewModel.upcomingAmount(payment, hidden: hidesBalances), secondaryAmount: nil)
    }

    @ViewBuilder
    private func draftButtons(_ transaction: Domain.Transaction) -> some View {
        // An assistant's movement can also be thrown away: it never happened.
        if transaction.source == .mcp, viewModel.canDiscardDrafts {
            Button {
                Task { await viewModel.discardDraft(transaction) }
            } label: {
                Text("Discard", bundle: #bundle)
            }
            .buttonStyle(.kw(.secondary, size: .mini))
        }
        Button {
            Task { await viewModel.confirm(transaction.id) }
        } label: {
            Text("Confirm", bundle: #bundle)
        }
        .buttonStyle(.kw(.primary, size: .mini))
        .disabled(viewModel.confirming.contains(transaction.id))
    }
}

/// A row of the "Upcoming" card: `KWTransactionRow`'s layout, with the day in the warning color
/// when it's overdue (the words say so too, so it never depends on color alone).
private struct UpcomingPaymentRow<Leading: View, Trailing: View>: View {
    let viewModel: HomeViewModel
    let payment: UpcomingPayment
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.upcomingTitle(payment))
                    .font(.kw(15, weight: 600))
                    .foregroundStyle(KWColor.Text.primary)
                Text(viewModel.upcomingSubtitle(payment))
                    .font(KWTextStyle.caption.font.weight(payment.status == .overdue ? .semibold : .regular))
                    .foregroundStyle(payment.status == .overdue ? KWColor.State.pending : KWColor.Text.muted)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.vertical, KWSpacing.sm)
        .contentShape(Rectangle())
    }
}
