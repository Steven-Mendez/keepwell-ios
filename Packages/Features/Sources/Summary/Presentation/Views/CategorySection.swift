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
                    ring(rows)
                        .frame(height: ringSize)
                        .frame(maxWidth: .infinity)
                }
                Text(viewModel.categoryCount)
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                KWGroupedCard(verticalPadding: 6) {
                    ForEach(rows) { row in
                        categoryRow(row)
                    }
                }
            }
        }
    }

    private func color(of row: SummaryViewModel.CategoryRow) -> Color {
        row.isOthers ? KWColor.Surface.controlOff : CategoryDisplay.color(for: row.category)
    }

    private func ring(_ rows: [SummaryViewModel.CategoryRow]) -> some View {
        Chart(rows) { row in
            SectorMark(
                angle: .value(ChartAxis.amount, row.share),
                innerRadius: .ratio(0.64),
                angularInset: 1.5,
            )
            .cornerRadius(4)
            .foregroundStyle(color(of: row))
            .accessibilityLabel(row.name)
            .accessibilityValue("\(row.amount), \(row.percent)")
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame, let center = viewModel.ringCenter {
                    let rect = geometry[frame]
                    VStack(spacing: 2) {
                        Text(center.amount)
                            .font(.kw(22, weight: 800, relativeTo: .title2))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(center.caption)
                            .font(KWTextStyle.caption.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                    }
                    .frame(width: rect.width * 0.55)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func categoryRow(_ row: SummaryViewModel.CategoryRow) -> some View {
        let color = color(of: row)
        return HStack(spacing: KWSpacing.sm) {
            Group {
                if row.isOthers {
                    CategorySymbol(symbol: "ellipsis", size: 20)
                } else {
                    CategorySymbol(row.category, size: 20)
                }
            }
            .foregroundStyle(row.isOthers ? KWColor.Text.secondary : color)
            .frame(width: 38, height: 38)
            .background(color.opacity(row.isOthers ? 0.5 : 0.15), in: Circle())
            .accessibilityHidden(true)
            VStack(spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(.kw(15, weight: 600, relativeTo: .subheadline)).lineLimit(2)
                    Spacer(minLength: KWSpacing.xs)
                    Text(row.amount)
                        .font(.kw(15, weight: 700, relativeTo: .subheadline))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(spacing: KWSpacing.xs) {
                    KWProgressBar(max(row.share, 0.02), fill: color)
                    // Sized by its text, not a fixed width: "100 %" no longer wraps, at any Dynamic Type size.
                    Text(row.percent)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, KWSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}
