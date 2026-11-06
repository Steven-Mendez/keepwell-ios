import DesignSystem
import Domain
import HomeDomain
import SharedPresentation
import SwiftUI

/// Home: a balance carousel on the brand hero, quick actions, the latest movements, the month so
/// far, planned movements waiting for confirmation and the balance of each account.
public struct HomeView: View {
    /// Where home leads. The root decides how each one is shown.
    public struct Actions {
        public var search: () -> Void
        public var summary: () -> Void
        public var settings: () -> Void
        public var accounts: () -> Void
        public var newMovement: (TransactionKind) -> Void
        public var payCard: () -> Void
        public var allPlanned: () -> Void
        public var allTransactions: () -> Void

        public init(
            search: @escaping () -> Void,
            summary: @escaping () -> Void,
            settings: @escaping () -> Void,
            accounts: @escaping () -> Void,
            newMovement: @escaping (TransactionKind) -> Void,
            payCard: @escaping () -> Void,
            allPlanned: @escaping () -> Void,
            allTransactions: @escaping () -> Void,
        ) {
            self.search = search
            self.summary = summary
            self.settings = settings
            self.accounts = accounts
            self.newMovement = newMovement
            self.payCard = payCard
            self.allPlanned = allPlanned
            self.allTransactions = allTransactions
        }
    }

    private let viewModel: HomeViewModel
    private let actions: Actions
    /// Kept on the device, not synced: hiding amounts is about who is looking at this screen.
    @AppStorage("home.hidesBalances") private var hidesBalances = false

    public init(viewModel: HomeViewModel, actions: Actions) {
        self.viewModel = viewModel
        self.actions = actions
    }

    /// The planned rows home lists before "See all".
    private let plannedPreviewCount = 2

    public var body: some View {
        ScrollView {
            VStack(spacing: KWSpacing.sm) {
                HomeHero(viewModel: viewModel, actions: actions, hidesBalances: $hidesBalances)
                if let overview = viewModel.overview {
                    content(overview)
                        .padding(.horizontal, KWLayout.gutter)
                }
            }
            .padding(.bottom, KWSpacing.md)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
    }

    // MARK: - Cards

    @ViewBuilder
    private func content(_ overview: HomeOverview) -> some View {
        if overview.hasTransactions {
            if !overview.recent.isEmpty {
                HomeRecentCard(viewModel: viewModel, overview: overview, hidesBalances: hidesBalances, onSeeAll: actions.allTransactions)
            }
            monthCard(overview)
        } else {
            KWEmptyState(
                icon: .home,
                title: String(localized: "No transactions yet", bundle: #bundle),
                message: String(
                    localized: "Log your first expense, income or transfer and you will see your month here.",
                    bundle: #bundle,
                ),
                actionTitle: String(localized: "Log transaction", bundle: #bundle),
            ) { actions.newMovement(.expense) }
                .padding(.vertical, KWSpacing.xl)
        }
        if !overview.planned.isEmpty {
            plannedCard(overview)
        }
        balancesCard(overview)
    }

    private func monthCard(_ overview: HomeOverview) -> some View {
        let month = overview.month
        let largest = max(month.income, month.expense)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                    Text(viewModel.spentTitle(overview))
                        .font(KWTextStyle.label.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                    Text(viewModel.visible(viewModel.money(month.expense, overview), hidden: hidesBalances))
                        .font(.kw(26, weight: 800, relativeTo: .title2))
                        .tracking(-0.5)
                        .monospacedDigit()
                }
                Spacer(minLength: KWSpacing.xs)
                if let badge = viewModel.savedBadge(overview) {
                    Text(badge)
                        .font(.kw(13, weight: 700, relativeTo: .footnote))
                        .foregroundStyle(KWColor.State.positive)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(KWColor.Tint.positive, in: Capsule())
                }
            }
            VStack(spacing: KWSpacing.xs) {
                comparisonRow(
                    String(localized: "Income", bundle: #bundle),
                    month.income,
                    of: largest,
                    fill: KWColor.State.positive,
                    overview,
                )
                comparisonRow(
                    String(localized: "Expenses", bundle: #bundle),
                    month.expense,
                    of: largest,
                    fill: KWColor.State.negative,
                    overview,
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    private func comparisonRow(
        _ label: String,
        _ amount: Decimal,
        of largest: Decimal,
        fill: Color,
        _ overview: HomeOverview,
    ) -> some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 64, alignment: .leading)
            KWProgressBar(largest > 0 ? NSDecimalNumber(decimal: amount / largest).doubleValue : 0, fill: fill, height: 8)
            Text(viewModel.visible(viewModel.money(amount, overview), hidden: hidesBalances))
                .monospacedDigit()
                .frame(minWidth: 76, alignment: .trailing)
        }
        .font(KWTextStyle.caption.font.weight(.regular))
        .foregroundStyle(KWColor.Text.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func plannedCard(_ overview: HomeOverview) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            HStack {
                Text(viewModel.plannedTitle(overview))
                    .font(KWTextStyle.heading.font)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: actions.allPlanned) {
                    Text("See all", bundle: #bundle)
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Brand.link)
                        .frame(minHeight: KWLayout.minTouch)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, -KWSpacing.sm)
            Text(viewModel.plannedCaption(overview, hidden: hidesBalances))
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let display = viewModel.display {
                ForEach(overview.planned.prefix(plannedPreviewCount)) { transaction in
                    KWTransactionRow(.planned, title: transaction.description, subtitle: display.subtitle(of: transaction)) {
                        Button {
                            Task { await viewModel.confirm(transaction.id) }
                        } label: {
                            Text("Confirm", bundle: #bundle)
                        }
                        .buttonStyle(.kw(.primary, size: .mini))
                        .disabled(viewModel.confirming.contains(transaction.id))
                    }
                    .padding(.vertical, -KWSpacing.sm)
                }
            }
            if let error = viewModel.actionError {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    private func balancesCard(_ overview: HomeOverview) -> some View {
        KWGroupedCard(horizontalPadding: 18, verticalPadding: 6) {
            ForEach(overview.balances) { line in
                balanceRow(
                    CardDisplay.name(of: line.account),
                    viewModel.visible(viewModel.formatter.string(line.balance), hidden: hidesBalances),
                )
            }
            if let debt = overview.cardDebt {
                balanceRow(
                    String(localized: "Cards (debt)", bundle: #bundle),
                    viewModel.visible(viewModel.formatter.string(debt), hidden: hidesBalances),
                    color: debt.amount < 0 && !hidesBalances ? KWColor.State.negative : nil,
                )
            }
        }
    }

    private func balanceRow(_ title: String, _ value: String, color: Color? = nil) -> some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer(minLength: KWSpacing.xs)
            Text(value)
                .font(.kw(15, weight: 600))
                .monospacedDigit()
                .foregroundStyle(color ?? KWColor.Text.primary)
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}
