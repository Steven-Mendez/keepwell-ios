import DesignSystem
import SwiftUI

/// Count, money in, money out and net of what the list shows (the web's totals strip), as a
/// 2x2 grid of cells separated by hairlines.
struct MovementTotalsStrip: View {
    let cells: [(title: String, value: String, tone: MovementTone)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
            ForEach(cells, id: \.title) { cell in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.title)
                        .font(KWTextStyle.captionSm.font)
                        .foregroundStyle(KWColor.Text.muted)
                    Text(cell.value)
                        .font(.kw(15, weight: 700))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(tint(cell.tone))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KWSpacing.md)
                .padding(.vertical, KWSpacing.xs)
                .background(KWColor.Surface.surface)
                .accessibilityElement(children: .combine)
            }
        }
        .background(KWColor.Surface.border)
        .clipShape(RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    private func tint(_ tone: MovementTone) -> Color {
        switch tone {
        case .neutral: KWColor.Text.primary
        case .positive: KWTransactionStyle.income.amountColor
        case .negative: KWTransactionStyle.expense.amountColor
        }
    }
}
