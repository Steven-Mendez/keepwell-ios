import DesignSystem
import Domain
import RecurringDomain
import SharedPresentation
import SwiftUI

/// "Recurring": what subscriptions cost per month and per year, then every rule by group with when
/// it falls next. Tapping a rule opens it; "+" adds one.
public struct RecurringView: View {
    private let viewModel: RecurringViewModel
    private let onBack: () -> Void
    private let onAdd: () -> Void
    private let onOpen: (UUID) -> Void
    /// The same eye as home: hiding amounts is about who's looking at the phone, on every screen.
    @AppStorage("home.hidesBalances") private var hidesBalances = false

    public init(
        viewModel: RecurringViewModel,
        onBack: @escaping () -> Void,
        onAdd: @escaping () -> Void,
        onOpen: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onAdd = onAdd
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
            KWCircleButton(.plus, style: .white, accessibilityLabel: String(localized: "Add recurring", bundle: #bundle), action: onAdd)
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

    private func row(_ rule: RecurringRule) -> some View {
        Button { onOpen(rule.id) } label: {
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
                Text(viewModel.amount(of: rule, hidden: hidesBalances))
                    .font(.kw(15, weight: 700))
                    .foregroundStyle(amountColor(rule))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, KWSpacing.sm)
            .contentShape(Rectangle())
            .opacity(rule.isPaused ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func icon(_ rule: RecurringRule) -> some View {
        if rule.kind == .transfer {
            KWTransactionIcon(.transfer)
        } else {
            let category = viewModel.category(of: rule)
            CategorySymbol(category, size: 18)
                .foregroundStyle(CategoryDisplay.color(for: category))
                .frame(width: 40, height: 40)
                .background(CategoryDisplay.color(for: category).opacity(0.16), in: Circle())
                .accessibilityHidden(true)
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
