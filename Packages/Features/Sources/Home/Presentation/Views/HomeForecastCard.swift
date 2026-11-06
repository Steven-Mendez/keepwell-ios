import DesignSystem
import Domain
import SwiftUI

/// "End of month": roughly what the bank and cash accounts will hold when the month closes, with
/// the lines that add up to it. Amounts follow "hide balances".
struct HomeForecastCard: View {
    let viewModel: HomeViewModel
    let forecast: BalanceForecast
    let hidesBalances: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                Text("End of month", bundle: #bundle)
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.forecastTotal(forecast, hidden: hidesBalances))
                    .font(.kw(26, weight: 800, relativeTo: .title2))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .foregroundStyle(forecast.total < 0 && !hidesBalances ? KWColor.State.negative : KWColor.Text.primary)
                Text(viewModel.forecastExplanation)
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: KWSpacing.xs) {
                ForEach(viewModel.forecastLines(forecast, hidden: hidesBalances)) { line in
                    HStack {
                        Text(line.title).lineLimit(1)
                        Spacer(minLength: KWSpacing.xs)
                        Text(line.amount).monospacedDigit()
                    }
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}
