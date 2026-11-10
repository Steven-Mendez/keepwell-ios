import DesignSystem
import Domain
import GoalsDomain
import SharedPresentation
import SwiftUI

/// "Savings goals": each goal with its progress and what to set aside, with "Add money" and
/// "Withdraw" on every row. Tapping a goal edits it; "+" creates one.
public struct GoalsView: View {
    @Bindable private var viewModel: GoalsViewModel
    private let onBack: () -> Void
    /// The same eye as home: hiding amounts is about who's looking at the phone, on every screen.
    @AppStorage("home.hidesBalances") private var hidesBalances = false

    public init(viewModel: GoalsViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                header
                if viewModel.state == .failed {
                    Text("We couldn't load your goals.", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.goals, id: \.goal.id) { progress in
                        GoalRow(
                            viewModel: viewModel,
                            progress: progress,
                            hidesBalances: hidesBalances,
                        )
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(item: $viewModel.editor) { editor in
            GoalEditorView(viewModel: editor, onDone: finish, onClose: { viewModel.editor = nil })
                .presentationDetents([.large])
                .presentationBackground(KWColor.Surface.bg)
        }
        .sheet(item: $viewModel.amountSheet) { sheet in
            GoalAmountSheet(viewModel: sheet, hidesBalances: hidesBalances, onDone: finish, onClose: { viewModel.amountSheet = nil })
                .presentationDetents([.medium])
                .presentationBackground(KWColor.Surface.bg)
        }
    }

    private func finish() {
        Task { await viewModel.sheetFinished() }
    }

    private var header: some View {
        HStack(spacing: KWSpacing.sm) {
            KWNavigationHeader(String(localized: "Savings goals", bundle: #bundle), style: .large, onBack: onBack)
            KWCircleButton(
                hidesBalances ? .eyeOff : .eye,
                accessibilityLabel: hidesBalances
                    ? String(localized: "Show amounts", bundle: #bundle)
                    : String(localized: "Hide amounts", bundle: #bundle),
            ) { hidesBalances.toggle() }
            KWCircleButton(.plus, style: .white, accessibilityLabel: String(localized: "New goal", bundle: #bundle)) {
                viewModel.newGoal()
            }
        }
    }

    private var emptyState: some View {
        KWEmptyState(
            icon: .wallet,
            title: String(localized: "No goals yet", bundle: #bundle),
            message: String(
                localized: "Save for a trip, an emergency fund or anything else, and see how much to set aside each month.",
                bundle: #bundle,
            ),
            actionTitle: String(localized: "New goal", bundle: #bundle),
            action: viewModel.newGoal,
        )
        .padding(.top, 96)
    }
}

/// One goal: badge, name, progress bar, "saved of target", the next step, and the money actions.
struct GoalRow: View {
    let viewModel: GoalsViewModel
    let progress: SavingsGoalProgress
    let hidesBalances: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Button { viewModel.edit(progress.goal.id) } label: {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            HStack(spacing: KWSpacing.xs) {
                Button { viewModel.addMoney(to: progress.goal.id) } label: {
                    Text("Add money", bundle: #bundle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.kw(.surface, size: .small))
                Button { viewModel.withdraw(from: progress.goal.id) } label: {
                    Text("Withdraw", bundle: #bundle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.kw(.surface, size: .small))
                .disabled(progress.goal.saved <= 0)
            }
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            HStack(spacing: KWSpacing.sm) {
                SavingsGoalBadge(progress.goal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.goal.name)
                        .font(.kw(15, weight: 600))
                        .lineLimit(1)
                    Text(viewModel.amounts(progress, hidden: hidesBalances))
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            KWProgressBar(
                viewModel.barFraction(progress),
                fill: progress.isReached ? KWColor.State.positive : KWColor.Brand.accent,
                height: 8,
            )
            Text(viewModel.hint(progress, hidden: hidesBalances))
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(hintColor)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
    }

    private var hintColor: Color {
        if progress.isReached {
            KWColor.State.positive
        } else if progress.isOverdue {
            KWColor.State.pending
        } else {
            KWColor.Text.muted
        }
    }
}

#Preview {
    GoalsPreview.list()
}
