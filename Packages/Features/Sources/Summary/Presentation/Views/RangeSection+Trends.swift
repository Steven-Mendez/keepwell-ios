import Charts
import DesignSystem
import SharedPresentation
import SwiftUI

extension RangeSection {
    // MARK: Savings

    var savings: some View {
        let points = viewModel.savingsPoints
        let labels = Dictionary(uniqueKeysWithValues: points.map { ($0.key, $0.label) })
        let shown = Set(viewModel.axisKeys(points.map(\.key)))
        let accent = KWColor.Brand.accent
        return card(
            title: String(localized: "Savings over time", bundle: #bundle),
            caption: viewModel.savingsTotal == nil ? nil : String(
                localized: "Running total of what you kept, month after month",
                bundle: #bundle,
            ),
        ) {
            HStack(spacing: KWSpacing.md) {
                legend(viewModel.currentLegend, accent)
                if viewModel.hasComparison {
                    legend(viewModel.comparisonLegend, KWColor.Text.faint)
                }
            }
            .accessibilityHidden(true)
            savingsChart(points, labels: labels, shown: shown)
        }
    }

    private func savingsChart(_ points: [SummaryViewModel.SavingsPoint], labels: [String: String], shown: Set<String>) -> some View {
        let accent = KWColor.Brand.accent
        return Chart {
            RuleMark(y: .value(ChartAxis.amount, 0))
                .foregroundStyle(KWColor.Text.faint.opacity(0.6))
                .accessibilityHidden(true)
            ForEach(points) { point in
                if let previous = point.previous {
                    LineMark(
                        x: .value(ChartAxis.month, point.key),
                        y: .value(ChartAxis.amount, previous),
                        series: .value("Series", "previous"),
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(KWColor.Text.faint)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .accessibilityHidden(true)
                }
                LineMark(
                    x: .value(ChartAxis.month, point.key),
                    y: .value(ChartAxis.amount, point.current),
                    series: .value("Series", "current"),
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .accessibilityLabel(String(localized: "Saved so far", bundle: #bundle) + ", " + point.name)
                .accessibilityValue(point.currentText)
                if points.count <= 12 {
                    PointMark(x: .value(ChartAxis.month, point.key), y: .value(ChartAxis.amount, point.current))
                        .symbolSize(24)
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .chartXAxis { monthAxis(labels: labels, shown: shown) }
        .chartYAxis { moneyAxis(currency: viewModel.report?.currency ?? "USD") }
        .frame(height: chartHeight)
    }

    // MARK: Top categories

    @ViewBuilder
    var categories: some View {
        let series = viewModel.categorySeries
        let labels = viewModel.categoryAxisLabels
        let shown = Set(viewModel.axisKeys(viewModel.rangeMonths.map(\.key)))
        card(
            title: String(localized: "Top categories over time", bundle: #bundle),
            caption: String(localized: "Your largest spending categories, month by month", bundle: #bundle),
        ) {
            if series.isEmpty {
                Text("No spending", bundle: #bundle)
                    .font(KWTextStyle.body.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, KWSpacing.lg)
            } else {
                KWFlowLayout(spacing: KWSpacing.sm) {
                    ForEach(series) { item in
                        legend(item.name, CategoryDisplay.color(for: item.category))
                    }
                }
                .accessibilityHidden(true)
                Chart(viewModel.categoryPoints) { point in
                    LineMark(
                        x: .value(ChartAxis.month, point.key),
                        y: .value(ChartAxis.amount, point.amount),
                        series: .value("Category", point.seriesID),
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Category", point.seriesID))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .accessibilityLabel(point.name)
                    .accessibilityValue(point.amountText)
                }
                .chartForegroundStyleScale(
                    domain: series.map(\.id),
                    range: series.map { CategoryDisplay.color(for: $0.category) },
                )
                .chartLegend(.hidden)
                .chartXAxis { monthAxis(labels: labels, shown: shown) }
                .chartYAxis { moneyAxis(currency: viewModel.report?.currency ?? "USD") }
                .frame(height: chartHeight)
            }
        }
    }
}
