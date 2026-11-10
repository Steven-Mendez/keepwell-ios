import DesignSystem
import Domain
import HomeDomain
import SwiftUI

/// The brand hero at the top of home: greeting and shortcuts, a swipeable carousel with net worth
/// and each balance, and the quick actions.
struct HomeHero: View {
    let viewModel: HomeViewModel
    let actions: HomeView.Actions
    @Binding var hidesBalances: Bool
    /// The moment the greeting and date line show; `nil` follows the clock minute by minute. Fixed
    /// only in snapshots, where "Good afternoon" vs "Good evening" must not depend on when they run.
    var fixedDate: Date?
    @Environment(\.colorScheme) private var colorScheme

    @State private var page = BalancePage.Kind.netWorth

    /// Fixed because a paged `TabView` inside a `ScrollView` has no height of its own.
    private let carouselHeight: CGFloat = 146

    var body: some View {
        VStack(spacing: KWSpacing.xl) {
            topBar
            if let overview = viewModel.overview {
                balances(overview)
            } else {
                Color.clear.frame(height: carouselHeight + 70)
            }
            quickActions
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWLayout.safeTop)
        .padding(.bottom, KWSpacing.xl)
        .kwBrandSurface()
        .background { background }
    }

    /// In dark mode the brand blue melts into the black screen. In light mode it can't melt into
    /// the light gray, so it ends as a blue panel with rounded bottom corners.
    @ViewBuilder
    private var background: some View {
        if colorScheme == .dark {
            LinearGradient(
                stops: [
                    .init(color: KWColor.Brand.b600, location: 0),
                    .init(color: KWColor.Brand.b900, location: 0.55),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
        } else {
            LinearGradient(colors: [KWColor.Brand.b600, KWColor.Brand.b700], startPoint: .top, endPoint: .bottom)
                .clipShape(UnevenRoundedRectangle(
                    bottomLeadingRadius: KWRadius.surface,
                    bottomTrailingRadius: KWRadius.surface,
                    style: .continuous,
                ))
        }
    }

    // MARK: - Top bar

    private func greeting(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.greeting(at: date))
                .font(.kw(22, weight: 800, relativeTo: .title2))
                .foregroundStyle(KWColor.Text.primary)
            Text(viewModel.dateLine(date))
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.onBrand)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var topBar: some View {
        HStack(spacing: KWSpacing.xs) {
            if let fixedDate {
                greeting(at: fixedDate)
            } else {
                TimelineView(.everyMinute) { context in
                    greeting(at: context.date)
                }
            }
            Spacer(minLength: KWSpacing.xs)
            KWCircleButton(
                .search,
                style: .translucent,
                accessibilityLabel: String(localized: "Search transactions", bundle: #bundle),
                action: actions.search,
            )
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

    // MARK: - Balances

    private func balances(_ overview: HomeOverview) -> some View {
        let pages = viewModel.balancePages(overview)
        return VStack(spacing: KWSpacing.sm) {
            TabView(selection: $page) {
                ForEach(pages) { item in
                    balancePage(item)
                        .tag(item.kind)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: carouselHeight)
            .padding(.horizontal, -KWLayout.gutter)
            if pages.count > 1 {
                pageDots(pages)
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
        }
    }

    private func balancePage(_ item: BalancePage) -> some View {
        let parts = viewModel.parts(item.amount, hidden: hidesBalances)
        return VStack(spacing: KWSpacing.xs) {
            Button {
                withAnimation(.snappy) { hidesBalances.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(item.title)
                        .lineLimit(1)
                    KWIconView(hidesBalances ? .eyeOff : .eye, size: 16)
                }
                .font(.kw(15, weight: 500))
                .foregroundStyle(KWColor.Text.onBrand)
                .frame(minHeight: KWLayout.minTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .accessibilityHint(hidesBalances
                ? String(localized: "Shows balances", bundle: #bundle)
                : String(localized: "Hides balances", bundle: #bundle))
            (Text(parts.whole).font(.kw(52, weight: 800, relativeTo: .largeTitle))
                + Text(parts.cents).font(.kw(30, weight: 800, relativeTo: .title)))
                .tracking(-1.5)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(KWColor.Text.primary)
                .contentTransition(.numericText())
                .accessibilityLabel(hidesBalances
                    ? String(localized: "Hidden", bundle: #bundle)
                    : viewModel.formatter.string(item.amount))
            captions(item)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KWLayout.gutter)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func captions(_ item: BalancePage) -> some View {
        if let caption = item.caption {
            Text(viewModel.visible(caption, hidden: hidesBalances))
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.onBrand)
                .monospacedDigit()
        }
        if let note = item.note {
            Text(note)
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.onBrand)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func pageDots(_ pages: [BalancePage]) -> some View {
        HStack(spacing: 6) {
            ForEach(pages) { item in
                Capsule()
                    .fill(item.kind == page ? KWColor.Text.primary : KWColor.Overlay.white18)
                    .frame(width: item.kind == page ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityHidden(true)
    }

    // MARK: - Quick actions

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
