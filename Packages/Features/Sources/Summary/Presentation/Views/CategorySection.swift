import Charts
import DesignSystem
import SharedPresentation
import SwiftUI

/// Where the month's money went (or came from) as a ring, with the list underneath as its legend.
struct CategorySection: View {
    @Bindable var viewModel: SummaryViewModel
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSectionHeader(String(localized: "By category", bundle: #bundle), style: .large) {
                KWSegmentedControl(
                    [
                        (value: SummaryViewModel.Mode.expenses, title: String(localized: "Expenses", bundle: #bundle)),
                        (value: .income, title: String(localized: "Income", bundle: #bundle)),
                    ],
                    selection: $viewModel.mode,
                    style: .compact,
                )
                .fixedSize()
            }
            let rows = viewModel.categoryRows
            if rows.isEmpty {
                SummaryCard {
                    Text(viewModel.categoriesEmptyMessage)
                        .font(KWTextStyle.body.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, KWSpacing.lg)
                }
            } else {
                SummaryCard {
                    CategoryRing(rows: rows, center: viewModel.ringCenter)
                        .frame(height: ringSize)
                        .frame(maxWidth: .infinity)
                }
                Text(viewModel.categoryCount)
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                KWGroupedCard(verticalPadding: 6) {
                    ForEach(rows) { row in
                        CategoryRowView(row: row)
                    }
                }
            }
            budgets
        }
    }

    /// Budgets only cap spending, so the income side has nothing to show here.
    @ViewBuilder
    private var budgets: some View {
        let rows = viewModel.mode == .expenses ? viewModel.budgetRows : []
        if !rows.isEmpty {
            KWSectionHeader(String(localized: "Budgets", bundle: #bundle), style: .large)
                .padding(.top, KWSpacing.xs)
            KWGroupedCard(verticalPadding: 6) {
                ForEach(rows) { row in
                    budgetRow(row)
                }
            }
        }
    }

    private func budgetRow(_ row: SummaryViewModel.BudgetRow) -> some View {
        let tint = CategoryDisplay.color(for: row.category)
        let fill = switch row.level {
        case .onTrack: KWColor.Brand.accent
        case .nearLimit: KWColor.State.pending
        case .exceeded: KWColor.State.negative
        }
        return HStack(spacing: KWSpacing.sm) {
            CategorySymbol(row.category, size: 20)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(.kw(15, weight: 600, relativeTo: .subheadline)).lineLimit(2)
                    Spacer(minLength: KWSpacing.xs)
                    Text(row.remaining)
                        .font(.kw(13, weight: 700, relativeTo: .footnote))
                        .foregroundStyle(row.level == .exceeded ? KWColor.State.negative : KWColor.Text.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                KWProgressBar(row.fraction, fill: fill)
                Text(row.progress)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, KWSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}
