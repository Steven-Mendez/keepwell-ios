import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// The way into savings goals, always on home so there's a place to create the first one. With
/// goals it previews the first in list order: the soonest one still open.
struct HomeGoalsCard: View {
    let viewModel: HomeViewModel
    let top: SavingsGoalProgress?
    let hidesBalances: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                HStack {
                    Text("Savings goals", bundle: #bundle)
                        .font(KWTextStyle.heading.font)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("See all", bundle: #bundle)
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Brand.link)
                }
                if let top {
                    topRow(top)
                } else {
                    Text("No goals yet", bundle: #bundle)
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func topRow(_ top: SavingsGoalProgress) -> some View {
        HStack(spacing: KWSpacing.sm) {
            SavingsGoalBadge(top.goal, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(top.goal.name)
                        .font(.kw(15, weight: 600))
                        .lineLimit(1)
                    Spacer(minLength: KWSpacing.xs)
                    Text(viewModel.goalAmounts(top, hidden: hidesBalances))
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                KWProgressBar(
                    viewModel.goalBarFraction(top),
                    fill: top.isReached ? KWColor.State.positive : KWColor.Brand.accent,
                )
            }
        }
    }
}
