import DesignSystem
import Domain
import RecurringDomain
import SharedPresentation
import SwiftUI

/// "Recurring": what subscriptions cost per month and per year, then every rule by group with when
/// it falls next. Tapping a rule opens it; "+" adds a subscription (the short form) or any rule.
public struct RecurringView: View {
    private let viewModel: RecurringViewModel
    private let onBack: () -> Void
    private let onAdd: () -> Void
    private let onAddSubscription: () -> Void
    private let onOpen: (UUID) -> Void
    /// The same eye as home: hiding amounts is about who's looking at the phone, on every screen.
    @AppStorage("home.hidesBalances") private var hidesBalances = false

    public init(
        viewModel: RecurringViewModel,
        onBack: @escaping () -> Void,
        onAdd: @escaping () -> Void,
        onAddSubscription: @escaping () -> Void,
        onOpen: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onAdd = onAdd
        self.onAddSubscription = onAddSubscription
        self.onOpen = onOpen
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                header
                if viewModel.state == .failed {
                    Text("We couldn't load your recurring movements.", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                } else if viewModel.isEmpty {
                    emptyState
                } else if viewModel.overview != nil {
                    totals
                    if let error = viewModel.actionError {
                        Text(error)
                            .font(KWTextStyle.caption.font)
                            .foregroundStyle(KWColor.State.negative)
                    }
                    ForEach(viewModel.sections) { section in
                        VStack(alignment: .leading, spacing: KWSpacing.xs) {
                            KWSectionHeader(section.group.title)
                            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                                ForEach(section.rules) { rule in
                                    row(rule)
                                }
                            }
                        }
                    }
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
    }

    private var header: some View {
        HStack(spacing: KWSpacing.sm) {
            KWNavigationHeader(String(localized: "Recurring", bundle: #bundle), style: .large, onBack: onBack)
            KWCircleButton(
                hidesBalances ? .eyeOff : .eye,
                accessibilityLabel: hidesBalances
                    ? String(localized: "Show amounts", bundle: #bundle)
                    : String(localized: "Hide amounts", bundle: #bundle),
            ) { hidesBalances.toggle() }
            Menu {
                Button(action: onAddSubscription) { Text("New subscription", bundle: #bundle) }
                Button(action: onAdd) { Text("New recurring", bundle: #bundle) }
            } label: {
                KWIconView(.plus, size: 20, lineWidth: 2.2)
                    .foregroundStyle(KWColor.Semantic.primaryForeground)
                    .frame(width: 40, height: 40)
                    .background(KWColor.Semantic.primary, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel(Text("Add recurring", bundle: #bundle))
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xxs) {
            Text("Subscriptions per month", bundle: #bundle)
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
            Text(viewModel.monthlyTotal(hidden: hidesBalances))
                .font(.kw(26, weight: 800, relativeTo: .title2))
                .tracking(-0.5)
                .monospacedDigit()
            Text(viewModel.yearlyTotal(hidden: hidesBalances))
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.secondary)
                .monospacedDigit()
            ForEach(viewModel.excludedSubscriptions, id: \.self) { line in
                Text(line)
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.secondary)
                    .monospacedDigit()
            }
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        KWEmptyState(
            icon: .subscription,
            title: String(localized: "Nothing recurring yet", bundle: #bundle),
            message: String(
                localized: "Add rent, a salary or a subscription once. Each time it's due, a draft waits on that day for you to confirm.",
                bundle: #bundle,
            ),
            actionTitle: String(localized: "Add recurring", bundle: #bundle),
            action: onAdd,
        )
        .padding(.top, 96)
    }

    /// While a draft the rule made waits from today or before, its state takes the date's place,
    /// with "Confirm" beside it; swiping the row left confirms too.
    private func row(_ rule: RecurringRule) -> some View {
        let pending = viewModel.pendingDraft(of: rule)
        return HStack(spacing: KWSpacing.sm) {
            Button { onOpen(rule.id) } label: { rowLabel(rule, pending: pending) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            if let pending {
                Button {
                    Task { await viewModel.confirm(pending) }
                } label: {
                    Text("Confirm", bundle: #bundle)
                }
                .buttonStyle(.kw(.primary, size: .mini))
                .disabled(viewModel.confirming.contains(pending.transaction.id))
                .accessibilityLabel(Text("Confirm \(pending.transaction.description)", bundle: #bundle))
            }
        }
        .kwSwipeAction(
            .check,
            tint: KWColor.State.positive,
            label: Text("Confirm", bundle: #bundle),
            isEnabled: pending != nil,
        ) {
            if let pending {
                Task { await viewModel.confirm(pending) }
            }
        }
    }

    private func rowLabel(_ rule: RecurringRule, pending: PendingRuleDraft?) -> some View {
        HStack(spacing: KWSpacing.sm) {
            icon(rule)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.kw(15, weight: 600))
                Text(viewModel.subtitle(of: rule))
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.amount(of: rule, hidden: hidesBalances))
                    .font(.kw(15, weight: 700))
                    .foregroundStyle(amountColor(rule))
                    .monospacedDigit()
                if let pending {
                    pendingState(pending)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.vertical, KWSpacing.sm)
        .contentShape(Rectangle())
        .opacity(rule.isPaused && pending == nil ? 0.5 : 1)
    }

    /// Overdue reads in the warning color, and says so in words too.
    private func pendingState(_ pending: PendingRuleDraft) -> some View {
        Text(viewModel.pendingLabel(pending))
            .font(KWTextStyle.caption.font.weight(pending.daysOverdue > 0 ? .semibold : .regular))
            .foregroundStyle(pending.daysOverdue > 0 ? KWColor.State.pending : KWColor.Text.primary)
    }

    @ViewBuilder
    private func icon(_ rule: RecurringRule) -> some View {
        if rule.kind == .transfer {
            KWTransactionIcon(.transfer)
        } else {
            let category = viewModel.category(of: rule)
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

#Preview {
    RecurringPreview.list()
}
