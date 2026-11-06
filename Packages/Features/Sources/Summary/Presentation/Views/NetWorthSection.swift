import Charts
import DesignSystem
import SwiftUI

/// Net worth at the end of each of the last twelve months: the latest value, how far it moved since
/// the first month shown, and the line between them. Amounts follow "hide balances", as on Home;
/// the line keeps its shape, which says nothing about the amounts.
struct NetWorthSection: View {
    let viewModel: SummaryViewModel
    @AppStorage("home.hidesBalances") private var hidesBalances = false
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 170
    @State private var rawSelection: String?

    var body: some View {
        if let summary = viewModel.netWorthSummary(hidden: hidesBalances) {
            let months = viewModel.netWorthMonths(hidden: hidesBalances)
            SummaryCard {
                VStack(alignment: .leading, spacing: KWSpacing.sm) {
                    header(summary)
                    chart(months)
                }
            }
        }
    }

    private func header(_ summary: SummaryViewModel.NetWorthSummary) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.xxs) {
            Text("Net worth", bundle: #bundle)
                .font(KWTextStyle.label.font)
                .accessibilityAddTraits(.isHeader)
            Text(summary.caption)
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
            Text(summary.amount)
                .font(.kw(26, weight: 800, relativeTo: .title2))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(summary.isNegative ? KWColor.State.negative : KWColor.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .padding(.top, KWSpacing.xxs)
            if let change = summary.change {
                SummaryPill(text: change, tone: summary.tone)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func chart(_ months: [SummaryViewModel.NetWorthMonth]) -> some View {
        let domain = Self.domain(of: months)
        return Chart {
            marks(months, floor: domain.lowerBound)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    let key = value.as(String.self)
                    Text(months.first { $0.key == key }?.label ?? "")
                        .font(.kw(11, weight: 500, relativeTo: .caption2))
                        .foregroundStyle(KWColor.Text.faint)
                }
            }
        }
        .chartYAxis {
            if hidesBalances {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(KWColor.Surface.divider)
                }
            } else {
                moneyAxis(currency: viewModel.report?.currency ?? "USD")
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $rawSelection)
        .frame(height: chartHeight)
    }

    @ChartContentBuilder
    private func marks(_ months: [SummaryViewModel.NetWorthMonth], floor: Double) -> some ChartContent {
        let selected = months.first { $0.key == rawSelection }
        ForEach(months) { month in
            AreaMark(
                x: .value(ChartAxis.month, month.key),
                yStart: .value(ChartAxis.amount, floor),
                yEnd: .value(ChartAxis.amount, month.value),
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(colors: [KWColor.Brand.link.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom),
            )
            .accessibilityHidden(true)
            LineMark(x: .value(ChartAxis.month, month.key), y: .value(ChartAxis.amount, month.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(KWColor.Brand.link)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .accessibilityLabel(month.monthName)
                .accessibilityValue(month.text)
        }
        if let selected {
            RuleMark(x: .value(ChartAxis.month, selected.key))
                .foregroundStyle(KWColor.Surface.divider)
                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    VStack(spacing: 2) {
                        Text(selected.monthName).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
                        Text(selected.text).font(.kw(13, weight: 700, relativeTo: .footnote)).monospacedDigit()
                    }
                    .padding(.horizontal, KWSpacing.xs)
                    .padding(.vertical, 6)
                    .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityHidden(true)
            PointMark(x: .value(ChartAxis.month, selected.key), y: .value(ChartAxis.amount, selected.value))
                .foregroundStyle(KWColor.Brand.link)
                .symbolSize(60)
                .accessibilityHidden(true)
        } else if let last = months.last {
            PointMark(x: .value(ChartAxis.month, last.key), y: .value(ChartAxis.amount, last.value))
                .foregroundStyle(KWColor.Brand.link)
                .symbolSize(60)
                .accessibilityHidden(true)
        }
    }

    /// Around the values rather than from zero, so a year's movement reads as a slope; the area
    /// fills down to the bottom of that range instead of to zero.
    private static func domain(of months: [SummaryViewModel.NetWorthMonth]) -> ClosedRange<Double> {
        let values = months.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0 ... 1 }
        let padding = max((high - low) * 0.15, abs(high) * 0.05, 1)
        return (low - padding) ... (high + padding)
    }
}
