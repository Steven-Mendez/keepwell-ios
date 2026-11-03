import DesignSystem
import Domain
import HomeDomain
import SwiftUI

/// The brand hero at the top of home: search, shortcuts, net worth and the quick actions.
struct HomeHero: View {
    let viewModel: HomeViewModel
    let actions: HomeView.Actions

    var body: some View {
        VStack(spacing: 28) {
            topBar
            if let overview = viewModel.overview {
                netWorth(overview)
            } else {
                Color.clear.frame(height: 150)
            }
            quickActions
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWLayout.safeTop)
        .padding(.bottom, KWSpacing.xl)
        .background {
            LinearGradient(
                stops: [
                    .init(color: KWColor.Brand.b600, location: 0),
                    .init(color: KWColor.Brand.b900, location: 0.55),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
        }
    }

    private func netWorth(_ overview: HomeOverview) -> some View {
        let parts = viewModel.netWorthParts(overview)
        let principal = overview.settings.principal
        return VStack(spacing: KWSpacing.xs) {
            Text("Net worth · \(principal)", bundle: #bundle)
                .font(.kw(15, weight: 500))
                .foregroundStyle(KWColor.Text.onBrand)
            (Text(parts.whole).font(.kw(52, weight: 800, relativeTo: .largeTitle))
                + Text(parts.cents).font(.kw(30, weight: 800, relativeTo: .title)))
                .tracking(-1.5)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(viewModel.formatter.string(overview.netWorth))
            if let line = viewModel.secondCurrencyLine(overview) {
                Text(line)
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.onBrand)
                    .monospacedDigit()
            }
            Button(action: actions.accounts) {
                Text(viewModel.countsLine(overview))
                    .font(.kw(15, weight: 600))
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(KWColor.Overlay.white18, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: KWSpacing.xs) {
            Button(action: actions.search) {
                HStack(spacing: KWSpacing.xs) {
                    KWIconView(.search, size: 18)
                    Text("Search transactions", bundle: #bundle)
                        .font(KWTextStyle.body.font)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(KWColor.Text.onBrand)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(KWColor.Overlay.white14, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            KWCircleButton(
                .chartBars,
                style: .translucent,
                accessibilityLabel: String(localized: "Summary", bundle: #bundle),
                action: actions.summary,
            )
            KWCircleButton(
                .settings,
                style: .translucent,
                accessibilityLabel: String(localized: "Settings", bundle: #bundle),
                action: actions.settings,
            )
        }
    }

    private var quickActions: some View {
        HStack(spacing: KWSpacing.xs) {
            KWActionButton(String(localized: "Expense", bundle: #bundle), icon: .plus, style: .translucent, captionSize: 13) {
                actions.newMovement(.expense)
            }
            KWActionButton(
                String(localized: "action.income", defaultValue: "Income", bundle: #bundle),
                icon: .arrowDown,
                style: .translucent,
                captionSize: 13,
            ) {
                actions.newMovement(.income)
            }
            KWActionButton(String(localized: "Move", bundle: #bundle), icon: .transfer, style: .translucent, captionSize: 13) {
                actions.newMovement(.transfer)
            }
            KWActionButton(
                String(localized: "Pay card", bundle: #bundle),
                icon: .creditCard,
                style: .translucent,
                captionSize: 13,
                action: actions.payCard,
            )
        }
    }
}
