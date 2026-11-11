import Charts
import DesignSystem
import SharedPresentation
import SwiftUI

private func color(of row: SummaryViewModel.CategoryRow) -> Color {
    row.isOthers ? KWColor.Surface.controlOff : CategoryDisplay.color(for: row.category)
}

/// The ring of a month or of a whole period, with the total in its middle.
struct CategoryRing: View {
    let rows: [SummaryViewModel.CategoryRow]
    let center: (amount: String, caption: String)?

    var body: some View {
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
                if let frame = proxy.plotFrame, let center {
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
}

/// One category under a ring: badge, name, amount, share and, in a period, how it changed.
struct CategoryRowView: View {
    let row: SummaryViewModel.CategoryRow

    var body: some View {
        let color = color(of: row)
        HStack(spacing: KWSpacing.sm) {
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
                    if let change = row.change {
                        Text(change.text)
                            .font(KWTextStyle.captionSm.font)
                            .foregroundStyle(change.tone == .neutral ? KWColor.Text.muted : change.tone.color)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.vertical, KWSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.change?.before ?? "")
    }
}
