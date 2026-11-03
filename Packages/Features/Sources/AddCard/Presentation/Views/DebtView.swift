import Core
import DesignSystem
import Domain
import SwiftUI

/// Step 3 · Debt and cycle (credit cards).
public struct DebtView: View {
    @Bindable private var viewModel: AddCardViewModel
    private let onBack: () -> Void
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case debt
        case secondDebt
        case limit
    }

    public init(viewModel: AddCardViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        KWFormScreen {
            form
        } footer: {
            Button {
                focus = nil
                Task { await viewModel.addCreditCard() }
            } label: {
                Text("Add card", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canAddCreditCard || viewModel.isSaving)
        }
        .kwKeyboardToolbar($focus, order: focusOrder)
    }

    private var focusOrder: [Field] {
        viewModel.debtMode == .dual && viewModel.second != nil ? [.debt, .secondDebt, .limit] : [.debt, .limit]
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            KWFlowHeader(.back, progress: (2, 2), action: onBack)
            Text("How the debt works", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
            if viewModel.second != nil {
                KWSectionHeader(String(localized: "Which currencies does it charge you in?", bundle: #bundle)).padding(.top, KWSpacing.xxs)
                VStack(spacing: KWSpacing.xs) {
                    ForEach([DebtMode.dual, .principal, .second], id: \.self) { mode in
                        modeButton(mode)
                    }
                }
            }
            KWSectionHeader(String(localized: "What you owe today", bundle: #bundle)).padding(.top, KWSpacing.xxs)
            KWGroupedCard {
                KWAmountFieldRow(
                    debtLabel(debtCurrency),
                    symbol: CurrencyFormatter.symbol(for: debtCurrency),
                    text: $viewModel.principalDebtText,
                )
                .kwFocused($focus, equals: .debt)
                if viewModel.debtMode == .dual, let second = viewModel.second {
                    KWAmountFieldRow(debtLabel(second), symbol: CurrencyFormatter.symbol(for: second), text: $viewModel.secondDebtText)
                        .kwFocused($focus, equals: .secondDebt)
                }
            }
            KWSectionHeader(String(localized: "Cycle (optional)", bundle: #bundle)).padding(.top, KWSpacing.xxs)
            cycle
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
    }

    private var cycle: some View {
        KWGroupedCard {
            KWAmountFieldRow(
                String(localized: "Limit", bundle: #bundle),
                symbol: CurrencyFormatter.symbol(for: debtCurrency),
                placeholder: String(localized: "Not set", bundle: #bundle),
                text: $viewModel.limitText,
            )
            .kwFocused($focus, equals: .limit)
            stepper(String(localized: "Cutoff day", bundle: #bundle), value: viewModel.cutoffDay) { viewModel.stepCutoff(by: $0) }
            stepper(String(localized: "Due day", bundle: #bundle), value: viewModel.dueDay) { viewModel.stepDue(by: $0) }
        }
    }

    private var debtCurrency: String {
        viewModel.debtMode == .second ? viewModel.second ?? viewModel.principal : viewModel.principal
    }

    private func debtLabel(_ currency: String) -> String {
        String(localized: "Debt in \(currency)", bundle: #bundle)
    }

    private func modeButton(_ mode: DebtMode) -> some View {
        let isSelected = mode == viewModel.debtMode
        return Button { viewModel.debtMode = mode } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.modeTitle(mode)).font(.kw(15, weight: 700))
                Text(viewModel.modeSubtitle(mode))
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(isSelected ? KWColor.Surface.controlOff : KWColor.Text.muted)
            }
            .foregroundStyle(isSelected ? Color.black : KWColor.Text.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, KWSpacing.md)
            .background(isSelected ? Color.white : KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWSpacing.md))
            .overlay(RoundedRectangle(cornerRadius: KWSpacing.md).strokeBorder(isSelected ? Color.white : KWColor.Surface.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func stepper(_ label: String, value: Int, step: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label).foregroundStyle(KWColor.Text.secondary).font(KWTextStyle.body.font)
            Spacer()
            HStack(spacing: 10) {
                stepButton("−", label: String(localized: "Decrease", bundle: #bundle)) { step(-1) }
                Text("\(value)")
                    .font(KWTextStyle.heading.font)
                    .monospacedDigit()
                    .frame(width: 28)
                stepButton("+", label: String(localized: "Increase", bundle: #bundle)) { step(1) }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(KWTextStyle.heading.font)
                .frame(width: 32, height: 32)
                .background(KWColor.Surface.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
