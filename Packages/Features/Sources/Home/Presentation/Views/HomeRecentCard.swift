import DesignSystem
import HomeDomain
import SharedPresentation
import SwiftUI

/// The latest movements with "See all", the way Revolut opens its home with what just happened.
/// Tapping one opens its detail.
struct HomeRecentCard: View {
    let viewModel: HomeViewModel
    let overview: HomeOverview
    let hidesBalances: Bool
    let onOpen: (UUID) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent", bundle: #bundle)
                .font(KWTextStyle.heading.font)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, KWSpacing.xxs)
            if let display = viewModel.display {
                ForEach(overview.recent) { transaction in
                    Button { onOpen(transaction.id) } label: {
                        KWTransactionRow(
                            display.style(of: transaction),
                            title: transaction.description,
                            subtitle: display.subtitle(of: transaction),
                            amount: viewModel.visible(display.amount(of: transaction), hidden: hidesBalances),
                            secondaryAmount: hidesBalances ? nil : display.secondaryAmount(of: transaction),
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}
