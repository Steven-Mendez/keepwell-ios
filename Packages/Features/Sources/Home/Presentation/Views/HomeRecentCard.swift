import DesignSystem
import HomeDomain
import SharedPresentation
import SwiftUI

/// The latest movements with "See all", the way Revolut opens its home with what just happened.
struct HomeRecentCard: View {
    let viewModel: HomeViewModel
    let overview: HomeOverview
    let hidesBalances: Bool
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent", bundle: #bundle)
                .font(KWTextStyle.heading.font)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, KWSpacing.xxs)
            if let display = viewModel.display {
                ForEach(overview.recent) { transaction in
                    KWTransactionRow(
                        display.style(of: transaction),
                        title: transaction.description,
                        subtitle: display.subtitle(of: transaction),
                        amount: viewModel.visible(display.amount(of: transaction), hidden: hidesBalances),
                        secondaryAmount: hidesBalances ? nil : display.secondaryAmount(of: transaction),
                    )
                }
            }
            Button(action: onSeeAll) {
                Text("See all", bundle: #bundle)
                    .font(KWTextStyle.label.font)
                    .foregroundStyle(KWColor.Brand.link)
                    .frame(maxWidth: .infinity, minHeight: KWLayout.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, -KWSpacing.xs)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}
