import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Monthly summary: six months of spending (or income) as bars with the average, what came in
/// and went out of the selected month, what was saved and where the money went by category.
public struct SummaryView: View {
    @Bindable private var viewModel: SummaryViewModel
    private let onNewMovement: () -> Void

    public init(viewModel: SummaryViewModel, onNewMovement: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onNewMovement = onNewMovement
    }

    /// Tallest bar and the room for the month labels under the bars.
    private let barHeight: CGFloat = 150
    private let labelArea: CGFloat = 26

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWLargeTitleHeader(String(localized: "Summary", bundle: #bundle)) {
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
                if viewModel.report != nil, !viewModel.hasMovements {
                    KWEmptyState(
                        icon: .chartBars,
                        title: String(localized: "Your summary starts with one transaction", bundle: #bundle),
                        message: viewModel.emptyMessage,
                        actionTitle: String(localized: "Log transaction", bundle: #bundle),
                        action: onNewMovement,
                    )
                    .padding(.top, 120)
                } else if viewModel.report != nil {
                    headline
                    chart
                    flowCards
                    savingsCard
                    categories
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.lg)
            .animation(.snappy, value: viewModel.mode)
            .animation(.snappy, value: viewModel.selectedIndex)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var headline: some View {
        if let headline = viewModel.headline {
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                Text(headline.title)
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                Text(headline.amount)
                    .kwTextStyle(.amountLg)
                    .contentTransition(.numericText())
                if let average = viewModel.averageLine {
                    HStack(spacing: 6) {
                        DashedLine().stroke(style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 14, height: 2)
                        Text(average.caption)
                    }
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Brand.link)
                    .monospacedDigit()
                }
            }
        }
    }

    private var chart: some View {
        let bars = viewModel.bars
        return ZStack(alignment: .bottom) {
            if let average = viewModel.averageLine {
                DashedLine()
                    .stroke(KWColor.Brand.link.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .frame(height: 2)
                    .padding(.bottom, labelArea + barHeight * average.fraction)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(bars) { bar in
                    barColumn(bar)
                }
            }
            // In front of the bars so a tall month never hides it.
            if let average = viewModel.averageLine {
                Text(average.label)
                    .font(.kw(11, weight: 700, relativeTo: .caption2))
                    .foregroundStyle(KWColor.Brand.link)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KWColor.Surface.bg, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, labelArea + barHeight * average.fraction - 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: barHeight + labelArea + 20)
    }

    private func barColumn(_ bar: SummaryViewModel.Bar) -> some View {
        let isSelected = bar.id == viewModel.selectedIndex
        let fill: Color = isSelected ? .white : (bar.isEmpty ? KWColor.Surface.surface2 : KWColor.Surface.controlOff)
        return Button { viewModel.selectedIndex = bar.id } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: bar.isEmpty ? 4 : 10, style: .continuous)
                    .fill(fill)
                    .frame(width: bar.isEmpty ? 8 : 30, height: bar.isEmpty ? 8 : max(12, barHeight * bar.fraction))
                Text(bar.label)
                    .font(.kw(12, weight: isSelected ? 800 : 500, relativeTo: .caption))
                    .foregroundStyle(isSelected ? KWColor.Text.primary : KWColor.Text.faint)
                    .lineLimit(1)
                    .frame(height: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bar.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var flowCards: some View {
        if let flow = viewModel.flow {
            HStack(spacing: 10) {
                flowCard(
                    String(localized: "Came in", bundle: #bundle),
                    flow.income,
                    fraction: flow.incomeFraction,
                    color: KWColor.State.positive,
                )
                flowCard(String(localized: "Went out", bundle: #bundle), flow.expense, fraction: flow.expenseFraction, color: .white)
            }
        }
    }

    private func flowCard(_ title: String, _ amount: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
            Text(amount)
                .font(.kw(20, weight: 800, relativeTo: .title3))
                .foregroundStyle(color == .white ? KWColor.Text.primary : color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            KWProgressBar(fraction, fill: color, height: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var savingsCard: some View {
        if let savings = viewModel.savings {
            let tint = savings.isNegative ? KWColor.State.negative : KWColor.State.positive
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved this month", bundle: #bundle)
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                    Text(savings.amount)
                        .font(.kw(20, weight: 800, relativeTo: .title3))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                }
                Spacer(minLength: KWSpacing.xs)
                Text(savings.rate)
                    .font(.kw(13, weight: 700, relativeTo: .footnote))
                    .foregroundStyle(tint)
                    .padding(.horizontal, KWSpacing.sm)
                    .frame(height: 30)
                    .background(savings.isNegative ? KWColor.Tint.negative : KWColor.Tint.positive, in: Capsule())
            }
            .padding(.horizontal, KWSpacing.md)
            .padding(.vertical, 14)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSectionHeader(String(localized: "By category", bundle: #bundle), style: .large) {
                Text(viewModel.categoryCount)
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
            }
            .padding(.top, KWSpacing.xxs)
            let rows = viewModel.categoryRows
            if !rows.isEmpty {
                KWGroupedCard(verticalPadding: 6) {
                    ForEach(rows) { row in
                        categoryRow(row)
                    }
                }
            }
        }
    }

    private func categoryRow(_ row: SummaryViewModel.CategoryRow) -> some View {
        let color = CategoryDisplay.color(for: row.category)
        return HStack(spacing: KWSpacing.sm) {
            CategorySymbol(row.category, size: 20)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: 7) {
                HStack {
                    Text(row.name).font(.kw(15, weight: 600)).lineLimit(1)
                    Spacer(minLength: KWSpacing.xs)
                    Text(row.amount).font(.kw(15, weight: 700)).monospacedDigit()
                }
                HStack(spacing: KWSpacing.xs) {
                    KWProgressBar(max(row.share, 0.02), fill: color)
                    Text(row.percent)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, KWSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// A horizontal line drawn through the middle of its frame, for dashed strokes.
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
