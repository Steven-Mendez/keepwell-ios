import Charts
import DesignSystem
import SharedPresentation
import SwiftUI

/// A period read as one: its four answers, then month by month, savings building up, the top
/// categories, highlights and every year side by side. Cards stack vertically on the phone.
struct RangeSection: View {
    let viewModel: SummaryViewModel
    @ScaledMetric(relativeTo: .body) var chartHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            Text(viewModel.rangeSubtitle)
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
            tiles
            monthByMonth
            savings
            categories
            highlights
            years
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(viewModel.rangeTiles) { tile in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let dot = tile.dot {
                            Circle().fill(dot.color).frame(width: 8, height: 8)
                        }
                        Text(tile.label)
                            .font(KWTextStyle.caption.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                            .lineLimit(1)
                    }
                    Text(tile.value)
                        .font(.kw(20, weight: 800, relativeTo: .title3))
                        .foregroundStyle(tile.tone == .neutral ? KWColor.Text.primary : tile.tone.color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let caption = tile.caption {
                        Text(caption)
                            .font(KWTextStyle.captionSm.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                    }
                    if let detail = tile.detail {
                        Text(detail.text)
                            .font(KWTextStyle.captionSm.font)
                            .foregroundStyle(detail.tone.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(KWSpacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Month by month

    private var monthByMonth: some View {
        let months = viewModel.rangeMonths
        let average = viewModel.rangeAverage
        let labels = Dictionary(uniqueKeysWithValues: months.map { ($0.key, $0.label) })
        let shown = Set(viewModel.axisKeys(months.map(\.key)))
        return card(title: String(localized: "Month by month", bundle: #bundle), caption: average?.text) {
            HStack(spacing: KWSpacing.md) {
                legend(String(localized: "Came in", bundle: #bundle), KWColor.State.positive)
                legend(String(localized: "Went out", bundle: #bundle), KWColor.State.negative)
            }
            .accessibilityHidden(true)
            Chart {
                ForEach(months) { month in
                    BarMark(x: .value(ChartAxis.month, month.key), y: .value(ChartAxis.amount, month.income), width: .ratio(0.8))
                        .position(by: .value(ChartAxis.direction, "in"))
                        .foregroundStyle(KWColor.State.positive)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                        .accessibilityLabel(month.name)
                        .accessibilityValue("\(month.incomeText), \(month.expenseText), \(month.netText)")
                    BarMark(x: .value(ChartAxis.month, month.key), y: .value(ChartAxis.amount, month.expense), width: .ratio(0.8))
                        .position(by: .value(ChartAxis.direction, "out"))
                        .foregroundStyle(KWColor.State.negative)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                        .accessibilityHidden(true)
                }
                if let average {
                    RuleMark(y: .value(ChartAxis.amount, average.value))
                        .foregroundStyle(KWColor.Text.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .accessibilityLabel(average.text)
                }
            }
            .chartXAxis { monthAxis(labels: labels, shown: shown) }
            .chartYAxis { moneyAxis(currency: viewModel.report?.currency ?? "USD") }
            .frame(height: chartHeight)
        }
    }

    // MARK: Highlights

    @ViewBuilder
    private var highlights: some View {
        let items = viewModel.highlights
        if !items.isEmpty {
            card(title: String(localized: "Highlights", bundle: #bundle), caption: viewModel.highlightsCaption) {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: KWSpacing.sm) {
                            Text(item.label)
                                .font(KWTextStyle.caption.font.weight(.regular))
                                .foregroundStyle(KWColor.Text.secondary)
                            Spacer(minLength: KWSpacing.xs)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(item.value).font(KWTextStyle.label.font).lineLimit(1)
                                if let detail = item.detail {
                                    Text(detail)
                                        .font(KWTextStyle.captionSm.font)
                                        .foregroundStyle(item.tone == .neutral ? KWColor.Text.muted : item.tone.color)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        if item.id != items.last?.id {
                            Divider().overlay(KWColor.Surface.divider)
                        }
                    }
                }
            }
        }
    }

    // MARK: Year over year

    @ViewBuilder
    private var years: some View {
        let bars = viewModel.yearBars
        if bars.count > 1 {
            card(
                title: String(localized: "Year over year", bundle: #bundle),
                caption: String(localized: "Every year you've logged, whatever range is picked above", bundle: #bundle),
            ) {
                HStack(spacing: KWSpacing.md) {
                    legend(String(localized: "Came in", bundle: #bundle), KWColor.State.positive)
                    legend(String(localized: "Went out", bundle: #bundle), KWColor.State.negative)
                    legend(String(localized: "Saved", bundle: #bundle), KWColor.Brand.accent)
                }
                .accessibilityHidden(true)
                Chart {
                    ForEach(bars) { year in
                        yearBar(year, "in", year.income, KWColor.State.positive)
                        yearBar(year, "out", year.expense, KWColor.State.negative)
                        yearBar(year, "net", year.net, year.tone == .negative ? KWColor.State.negative.opacity(0.55) : KWColor.Brand.accent)
                    }
                    RuleMark(y: .value(ChartAxis.amount, 0))
                        .foregroundStyle(KWColor.Text.faint.opacity(0.6))
                        .accessibilityHidden(true)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(.kw(11, weight: 500, relativeTo: .caption2)).foregroundStyle(KWColor.Text.faint)
                    }
                }
                .chartYAxis { moneyAxis(currency: viewModel.report?.currency ?? "USD") }
                .frame(height: chartHeight)
            }
        }
    }

    @ChartContentBuilder
    private func yearBar(_ year: SummaryViewModel.YearBar, _ position: String, _ value: Double, _ color: Color) -> some ChartContent {
        BarMark(x: .value(ChartAxis.month, year.label), y: .value(ChartAxis.amount, value), width: .ratio(0.9))
            .position(by: .value(ChartAxis.direction, position))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel(year.label)
            .accessibilityValue("\(year.incomeText), \(year.expenseText), \(year.netText)")
    }

    // MARK: Pieces

    func card(title: String, caption: String?, @ViewBuilder content: () -> some View) -> some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(KWTextStyle.heading.font).accessibilityAddTraits(.isHeader)
                    if let caption {
                        Text(caption)
                            .font(KWTextStyle.caption.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                    }
                }
                content()
            }
        }
    }

    func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title)
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.secondary)
                .lineLimit(1)
        }
    }

    func monthAxis(labels: [String: String], shown: Set<String>) -> some AxisContent {
        AxisMarks { value in
            if let key = value.as(String.self), shown.contains(key) {
                AxisValueLabel {
                    Text(labels[key] ?? "")
                        .font(.kw(11, weight: 500, relativeTo: .caption2))
                        .foregroundStyle(KWColor.Text.faint)
                }
            }
        }
    }
}
