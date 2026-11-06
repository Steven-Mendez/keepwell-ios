import DesignSystem
import Domain
import HomeDomain
import SharedPresentation
import SwiftUI

/// The next recurring movements this week, so a rent or a renewal never arrives unannounced.
struct HomeUpcomingCard: View {
    let viewModel: HomeViewModel
    let occurrences: [RecurringOccurrence]
    let hidesBalances: Bool
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Upcoming", bundle: #bundle)
                    .font(KWTextStyle.heading.font)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onSeeAll) {
                    Text("See all", bundle: #bundle)
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Brand.link)
                        .frame(minHeight: KWLayout.minTouch)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, -KWSpacing.sm)
            .padding(.bottom, KWSpacing.xxs)
            ForEach(occurrences, id: \.self) { occurrence in
                KWTransactionRow(
                    .planned,
                    title: occurrence.rule.name,
                    subtitle: viewModel.upcomingSubtitle(occurrence),
                    amount: viewModel.upcomingAmount(occurrence, hidden: hidesBalances),
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}
