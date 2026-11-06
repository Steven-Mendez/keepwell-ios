import DesignSystem
import SwiftUI

/// Subscriptions whose latest charge cost more than the one before. The amounts follow "hide
/// balances"; the warning itself stays, like budget alerts.
struct HomePriceIncreasesCard: View {
    let alerts: [HomeViewModel.PriceIncreaseAlert]
    let hidesBalances: Bool

    var body: some View {
        KWGroupedCard(horizontalPadding: 18, verticalPadding: 6) {
            ForEach(alerts) { alert in
                HStack(spacing: KWSpacing.sm) {
                    KWIconView(.subscription, size: 18)
                        .foregroundStyle(KWColor.State.pending)
                        .frame(width: 36, height: 36)
                        .background(KWColor.State.pending.opacity(0.15), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(.kw(15, weight: 600, relativeTo: .subheadline))
                            .fixedSize(horizontal: false, vertical: true)
                        if !hidesBalances {
                            Text(alert.body)
                                .font(KWTextStyle.caption.font.weight(.regular))
                                .foregroundStyle(KWColor.Text.muted)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, KWSpacing.sm)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
