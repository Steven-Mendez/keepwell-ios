import DesignSystem
import SharedPresentation
import SwiftUI

/// Categories close to or over their monthly budget this month. The amounts follow "hide
/// balances"; the warning itself stays, since knowing a budget ran out isn't the sensitive part.
struct HomeBudgetAlertsCard: View {
    let alerts: [HomeViewModel.BudgetAlert]
    let hidesBalances: Bool

    var body: some View {
        KWGroupedCard(verticalPadding: 6) {
            ForEach(alerts) { alert in
                row(alert)
            }
        }
    }

    private func row(_ alert: HomeViewModel.BudgetAlert) -> some View {
        let color = alert.level == .exceeded ? KWColor.State.negative : KWColor.State.pending
        return HStack(spacing: KWSpacing.sm) {
            CategorySymbol(alert.category, size: 18)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15), in: Circle())
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
