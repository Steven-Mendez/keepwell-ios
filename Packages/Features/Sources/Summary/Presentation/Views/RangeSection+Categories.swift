import DesignSystem
import SwiftUI

extension RangeSection {
    /// Where the money went (or came from) in the period: the ring, then each category against the
    /// comparison. The same Expenses / Income switch as the month view.
    var byCategory: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
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
            if let caption = viewModel.rangeCategoriesCaption {
                Text(caption)
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
            }
            let rows = viewModel.rangeCategoryRows
            if rows.isEmpty {
                SummaryCard {
                    Text(viewModel.rangeCategoriesEmpty)
                        .font(KWTextStyle.body.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KWSpacing.lg)
                }
            } else {
                SummaryCard {
                    CategoryRing(rows: viewModel.rangeRingRows, center: viewModel.rangeRingCenter)
                        .frame(height: ringSize)
                        .frame(maxWidth: .infinity)
                }
                KWGroupedCard(verticalPadding: 6) {
                    ForEach(rows) { row in
                        CategoryRowView(row: row)
                    }
                }
            }
        }
    }
}
