import Charts
import DesignSystem
import SwiftUI

/// Running spending this month against last month, day by day: a line above last month's means
/// spending runs ahead, while there is still time to slow down.
struct PaceSection: View {
    let viewModel: SummaryViewModel
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 210

    var body: some View {
        if let summary = viewModel.paceSummary {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                headline(summary)
                SummaryCard {
                    VStack(alignment: .leading, spacing: KWSpacing.sm) {
                        legend(summary)
                        chart(summary)
                        Text(summary.previousTotal)
                            .font(KWTextStyle.caption.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func headline(_ summary: SummaryViewModel.PaceSummary) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.xxs) {
            Text(summary.title)
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
            Text(summary.amount)
                .kwTextStyle(.amountLg)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if let comparison = summary.comparison {
                SummaryPill(text: comparison, tone: summary.tone)
                    .padding(.top, KWSpacing.xxs)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func legend(_ summary: SummaryViewModel.PaceSummary) -> some View {
        HStack(spacing: KWSpacing.md) {
            HStack(spacing: 6) {
                Capsule().fill(KWColor.Text.primary).frame(width: 14, height: 3)
                Text(summary.currentLegend)
            }
            HStack(spacing: 6) {
                DashSample().stroke(KWColor.Text.faint, style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 14, height: 3)
                Text(summary.previousLegend)
            }
        }
        .font(KWTextStyle.captionSm.font)
        .foregroundStyle(KWColor.Text.secondary)
        .accessibilityHidden(true)
    }

    private func chart(_ summary: SummaryViewModel.PaceSummary) -> some View {
        Chart {
            marks(summary)
        }
        .chartXScale(domain: 1 ... summary.dayCount)
        .chartXAxis {
            AxisMarks(values: [1, 8, 15, 22, summary.dayCount]) { value in
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text(day, format: .number)
                            .font(.kw(11, weight: 500, relativeTo: .caption2))
                            .foregroundStyle(KWColor.Text.faint)
                    }
                }
            }
        }
        .chartYAxis {
            moneyAxis(currency: viewModel.report?.currency ?? "USD")
        }
        .frame(height: chartHeight)
        // Sixty points read one by one say less than the comparison itself.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilitySummary)
    }

    @ChartContentBuilder
    private func marks(_ summary: SummaryViewModel.PaceSummary) -> some ChartContent {
        let points = viewModel.pacePoints
        let current = points.filter { $0.series == .selected }
        ForEach(points.filter { $0.series == .previous }) { point in
            LineMark(
                x: .value(ChartAxis.day, point.day),
                y: .value(ChartAxis.amount, point.cumulative),
                series: .value(ChartAxis.month, summary.previousLegend),
            )
            .interpolationMethod(.stepEnd)
            .foregroundStyle(KWColor.Text.faint)
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
        }
        ForEach(current) { point in
            AreaMark(x: .value(ChartAxis.day, point.day), y: .value(ChartAxis.amount, point.cumulative))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(
                    LinearGradient(colors: [summary.tone.color.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom),
                )
            LineMark(
                x: .value(ChartAxis.day, point.day),
                y: .value(ChartAxis.amount, point.cumulative),
                series: .value(ChartAxis.month, summary.currentLegend),
            )
            .interpolationMethod(.stepEnd)
            .foregroundStyle(KWColor.Text.primary)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        if let last = current.last {
            PointMark(x: .value(ChartAxis.day, last.day), y: .value(ChartAxis.amount, last.cumulative))
                .foregroundStyle(summary.tone == .neutral ? KWColor.Text.primary : summary.tone.color)
                .symbolSize(70)
        }
    }
}

private struct DashSample: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
