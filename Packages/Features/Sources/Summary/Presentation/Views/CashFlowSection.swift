import Charts
import DesignSystem
import SwiftUI

/// Income next to spending per month, then a result strip where each month is a green bar up
/// (saved) or a red bar down (overspent): the answer is read from the color, not by subtracting.
struct CashFlowSection: View {
    let viewModel: SummaryViewModel
    @State private var rawSelection: String?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 170
    @ScaledMetric(relativeTo: .body) private var netHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            headline
            SummaryCard {
                VStack(alignment: .leading, spacing: KWSpacing.sm) {
                    legend
                    flowChart
                    Divider().overlay(KWColor.Surface.divider)
                    Text("Result per month", bundle: #bundle)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                    netChart
                }
            }
            flowCards
            windowCard
        }
        .onChange(of: rawSelection) { _, key in
            if let key {
                viewModel.selectMonth(key: key)
            }
        }
    }

    @ViewBuilder
    private var headline: some View {
        if let headline = viewModel.flowHeadline {
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                Text(headline.title)
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                Text(headline.amount)
                    .kwTextStyle(.amountLg)
                    .foregroundStyle(headline.tone == .neutral ? KWColor.Text.primary : headline.tone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                if let detail = headline.detail {
                    SummaryPill(text: detail, tone: headline.tone)
                        .padding(.top, KWSpacing.xxs)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var legend: some View {
        HStack(spacing: KWSpacing.md) {
            legendItem(String(localized: "Came in", bundle: #bundle), color: KWColor.State.positive)
            legendItem(String(localized: "Went out", bundle: #bundle), color: KWColor.State.negative)
        }
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title)
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.secondary)
        }
    }

    private var flowChart: some View {
        let months = viewModel.flowMonths
        return Chart(months) { month in
            let isSelected = month.id == viewModel.selectedIndex
            BarMark(
                x: .value(ChartAxis.month, month.key),
                y: .value(ChartAxis.amount, month.income),
                width: .ratio(0.8),
            )
            .position(by: .value(ChartAxis.direction, "in"))
            .foregroundStyle(KWColor.State.positive.opacity(isSelected ? 1 : 0.35))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            .accessibilityLabel(month.incomeLabel)
            .accessibilityValue(month.incomeText)
            BarMark(
                x: .value(ChartAxis.month, month.key),
                y: .value(ChartAxis.amount, month.expense),
                width: .ratio(0.8),
            )
            .position(by: .value(ChartAxis.direction, "out"))
            .foregroundStyle(KWColor.State.negative.opacity(isSelected ? 1 : 0.35))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            .accessibilityLabel(month.expenseLabel)
            .accessibilityValue(month.expenseText)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    let key = value.as(String.self)
                    let month = months.first { $0.key == key }
                    Text(month?.label ?? "")
                        .font(.kw(12, weight: month?.id == viewModel.selectedIndex ? 800 : 500, relativeTo: .caption))
                        .foregroundStyle(month?.id == viewModel.selectedIndex ? KWColor.Text.primary : KWColor.Text.faint)
                }
            }
        }
        .chartYAxis {
            moneyAxis(currency: viewModel.report?.currency ?? "USD")
        }
        .chartXSelection(value: $rawSelection)
        .frame(height: chartHeight)
    }

    private var netChart: some View {
        let months = viewModel.flowMonths
        return Chart {
            ForEach(months) { month in
                netBar(month)
            }
            RuleMark(y: .value(ChartAxis.result, 0))
                .foregroundStyle(KWColor.Text.faint.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .accessibilityHidden(true)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(range: .plotDimension(padding: 16))
        .chartXSelection(value: $rawSelection)
        .frame(height: netHeight)
    }

    @ChartContentBuilder
    private func netBar(_ month: SummaryViewModel.FlowMonth) -> some ChartContent {
        let isSelected = month.id == viewModel.selectedIndex
        BarMark(
            x: .value(ChartAxis.month, month.key),
            y: .value(ChartAxis.result, month.net),
            width: .ratio(0.45),
        )
        .foregroundStyle(month.tone.color.opacity(isSelected ? 1 : 0.45))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .annotation(position: month.net < 0 ? .bottom : .top, spacing: 2) {
            Text(month.netLabel)
                .font(.kw(10, weight: isSelected ? 800 : 600, relativeTo: .caption2))
                .foregroundStyle(month.tone.color)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityLabel(month.monthName)
        .accessibilityValue(month.netText)
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
                flowCard(
                    String(localized: "Went out", bundle: #bundle),
                    flow.expense,
                    fraction: flow.expenseFraction,
                    color: KWColor.State.negative,
                )
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
                .foregroundStyle(color)
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
    private var windowCard: some View {
        if let window = viewModel.windowSummary {
            SummaryCard {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        windowTexts(window)
                        Spacer(minLength: KWSpacing.xs)
                        windowAmount(window)
                    }
                    VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                        windowTexts(window)
                        windowAmount(window)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func windowTexts(_ window: SummaryViewModel.WindowSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(window.title)
                .font(KWTextStyle.label.font)
            Text(window.detail)
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
        }
    }

    private func windowAmount(_ window: SummaryViewModel.WindowSummary) -> some View {
        Text(window.amount)
            .font(.kw(20, weight: 800, relativeTo: .title3))
            .foregroundStyle(window.tone.color)
            .monospacedDigit()
            .lineLimit(1)
    }
}
