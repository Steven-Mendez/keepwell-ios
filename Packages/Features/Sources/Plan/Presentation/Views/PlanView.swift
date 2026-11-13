import DesignSystem
import Domain
import PlanDomain
import SharedPresentation
import SwiftUI

/// The Plan tab: a card each for recurring movements, savings goals and debts, summarizing the
/// screen it opens.
public struct PlanView: View {
    private let viewModel: PlanViewModel
    private let onOpenRecurring: () -> Void
    private let onOpenGoals: () -> Void
    private let onOpenDebts: () -> Void
    /// The same eye as home: hiding amounts is about who's looking at the phone, on every screen.
    @AppStorage("home.hidesBalances") private var hidesBalances = false

    public init(
        viewModel: PlanViewModel,
        onOpenRecurring: @escaping () -> Void,
        onOpenGoals: @escaping () -> Void,
        onOpenDebts: @escaping () -> Void,
    ) {
        self.viewModel = viewModel
        self.onOpenRecurring = onOpenRecurring
        self.onOpenGoals = onOpenGoals
        self.onOpenDebts = onOpenDebts
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWLargeTitleHeader(String(localized: "Plan", bundle: #bundle)) {
                    KWCircleButton(
                        hidesBalances ? .eyeOff : .eye,
                        accessibilityLabel: hidesBalances
                            ? String(localized: "Show amounts", bundle: #bundle)
                            : String(localized: "Hide amounts", bundle: #bundle),
                    ) { hidesBalances.toggle() }
                }
                if let overview = viewModel.overview {
                    recurringCard(overview.recurring)
                    goalsCard(overview.goals)
                    debtsCard(overview.debts)
                } else if viewModel.state == .failed {
                    Text("We couldn't load your plan.", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
    }

    // MARK: - Cards

    private func recurringCard(_ recurring: PlanOverview.Recurring) -> some View {
        PlanCard(
            title: String(localized: "Recurring", bundle: #bundle),
            icon: .subscription,
            tint: KWSettingsTint.reminders,
            action: onOpenRecurring,
        ) {
            if recurring.hasRules {
                VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                    Text(viewModel.subscriptionsPerMonth(recurring, hidden: hidesBalances))
                        .font(.kw(26, weight: 800, relativeTo: .title2))
                        .tracking(-0.5)
                        .monospacedDigit()
                    Text(viewModel.subscriptionsCaption(recurring))
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                    ForEach(viewModel.excludedSubscriptionLines(recurring), id: \.self) { line in
                        Text(line)
                            .font(KWTextStyle.caption.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                    }
                }
                if let next = viewModel.nextRecurringLine(recurring) {
                    detail(next)
                }
            } else {
                emptyLine(String(localized: "Nothing recurring yet", bundle: #bundle))
            }
        }
    }

    private func goalsCard(_ goals: PlanOverview.Goals) -> some View {
        PlanCard(
            title: String(localized: "Savings goals", bundle: #bundle),
            icon: .calendarCheck,
            tint: KWSettingsTint.money,
            action: onOpenGoals,
        ) {
            if let top = goals.top {
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
                        HStack(spacing: KWSpacing.xs) {
                            KWProgressBar(
                                viewModel.goalBarFraction(top),
                                fill: top.isReached ? KWColor.State.positive : KWColor.Brand.accent,
                            )
                            Text(viewModel.goalPercent(top))
                                .font(KWTextStyle.captionSm.font)
                                .foregroundStyle(KWColor.Text.muted)
                                .monospacedDigit()
                        }
                    }
                }
                detail(viewModel.goalCount(goals))
            } else {
                emptyLine(String(localized: "No goals yet", bundle: #bundle))
            }
        }
    }

    private func debtsCard(_ debts: PlanOverview.Debts) -> some View {
        PlanCard(
            title: String(localized: "Debts", bundle: #bundle),
            icon: .bank,
            tint: KWSettingsTint.data,
            action: onOpenDebts,
        ) {
            if debts.hasDebts {
                HStack(alignment: .top, spacing: KWSpacing.md) {
                    total(
                        viewModel.youOweTitle(debts),
                        viewModel.debtTotal(debts.totals.youOwe, hidden: hidesBalances),
                        color: debts.totals.youOwe.isEmpty ? KWColor.Text.muted : KWColor.State.negative,
                    )
                    total(
                        viewModel.owedToYouTitle(debts),
                        viewModel.debtTotal(debts.totals.owedToYou, hidden: hidesBalances),
                        color: debts.totals.owedToYou.isEmpty ? KWColor.Text.muted : KWColor.State.positive,
                    )
                }
                if let line = viewModel.nextInstallmentLine(debts, hidden: hidesBalances) {
                    detail(line, color: debts.nextLoan?.isNextOverdue == true ? KWColor.State.pending : KWColor.Text.secondary)
                }
            } else {
                emptyLine(String(localized: "No debts yet", bundle: #bundle))
            }
        }
    }

    // MARK: - Pieces

    private func detail(_ text: String, color: Color = KWColor.Text.secondary) -> some View {
        Text(text)
            .font(KWTextStyle.caption.font.weight(.regular))
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(2)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(KWTextStyle.caption.font.weight(.regular))
            .foregroundStyle(KWColor.Text.muted)
    }

    private func total(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
            Text(value)
                .font(.kw(15, weight: 600))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tappable summary: a tinted icon, the screen's name and a chevron over what it holds.
private struct PlanCard<Content: View>: View {
    let title: String
    let icon: KWIcon
    let tint: Color
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                HStack(spacing: KWSpacing.sm) {
                    KWSettingsIcon(icon, tint: tint)
                    Text(title)
                        .font(KWTextStyle.heading.font)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: KWSpacing.xs)
                    KWIconView(.chevronRight, size: 16, lineWidth: 2.4)
                        .foregroundStyle(KWColor.Text.faint)
                }
                content
            }
            .padding(KWSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PlanView(viewModel: PlanPreview.viewModel(), onOpenRecurring: {}, onOpenGoals: {}, onOpenDebts: {})
        .onAppear { KWFonts.register() }
}
