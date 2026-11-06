import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// "Add money" or "Withdraw": one amount in the goal's currency.
struct GoalAmountSheet: View {
    @Bindable var viewModel: GoalAmountViewModel
    let hidesBalances: Bool
    let onDone: () -> Void
    let onClose: () -> Void
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.close, action: onClose)
            HStack(spacing: KWSpacing.sm) {
                SavingsGoalBadge(viewModel.goal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.title).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                    Text(viewModel.goal.name)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .lineLimit(1)
                }
            }
            KWGroupedCard {
                KWAmountFieldRow(
                    String(localized: "Amount", bundle: #bundle),
                    hint: savedLine,
                    symbol: CurrencyFormatter.symbol(for: viewModel.goal.target.currency),
                    text: $viewModel.amountText,
                )
                .focused($isAmountFocused)
            }
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
            Spacer(minLength: 0)
            Button {
                KWKeyboard.dismiss()
                Task {
                    if await viewModel.save() {
                        onDone()
                    }
                }
            } label: {
                Text(viewModel.title)
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canSave)
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.xl)
        .padding(.bottom, KWSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .onAppear { isAmountFocused = true }
        .onChange(of: isAmountFocused) { _, isFocused in
            if !isFocused {
                viewModel.formatAmount()
            }
        }
    }

    /// "C$4,500.00 of C$15,000.00", so the person sees what there is before moving any of it.
    private var savedLine: String {
        let formatter = CurrencyFormatter()
        let goal = viewModel.goal
        let saved = hidesBalances ? GoalsViewModel.maskedAmount : formatter.string(goal.savedMoney)
        let target = hidesBalances ? GoalsViewModel.maskedAmount : formatter.string(goal.target)
        return String(localized: "\(saved) of \(target)", bundle: #bundle)
    }
}
