import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Step 3 · Deuda y ciclo (credit cards).
public struct DebtView: View {
    @Bindable private var viewModel: AddCardViewModel
    private let onBack: () -> Void

    public init(viewModel: AddCardViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                form
                    .padding(.horizontal, KWLayout.gutter)
                    .padding(.top, KWLayout.safeTop)
                    .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            Button("Agregar tarjeta") { Task { await viewModel.addCreditCard() } }
                .buttonStyle(.kw())
                .disabled(!viewModel.canAddCreditCard || viewModel.isSaving)
                .padding(.horizontal, KWLayout.gutter)
                .padding(.top, KWSpacing.sm)
                .padding(.bottom, 34)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            KWFlowHeader(.back, progress: (2, 2), action: onBack)
            HStack(spacing: KWSpacing.sm) {
                KWMiniCard(.palette(CardDisplay.palette(for: viewModel.color)), size: .medium)
                Text("Cómo funciona la deuda").kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
            }
            if viewModel.second != nil {
                KWSectionHeader("¿En qué monedas te cobra?").padding(.top, KWSpacing.xxs)
                VStack(spacing: KWSpacing.xs) {
                    ForEach([DebtMode.dual, .principal, .second], id: \.self) { mode in
                        modeButton(mode)
                    }
                }
            }
            KWSectionHeader("Lo que debes hoy").padding(.top, KWSpacing.xxs)
            KWGroupedCard {
                FormAmountRow(label: "Deuda en \(debtCurrency)", text: $viewModel.principalDebtText)
                if viewModel.debtMode == .dual, let second = viewModel.second {
                    FormAmountRow(label: "Deuda en \(second)", text: $viewModel.secondDebtText)
                }
            }
            KWSectionHeader("Ciclo (opcional)").padding(.top, KWSpacing.xxs)
            KWGroupedCard {
                FormAmountRow(label: "Límite", text: $viewModel.limitText, placeholder: "Sin definir", filled: false)
                stepper("Día de corte", value: viewModel.cutoffDay) { viewModel.stepCutoff(by: $0) }
                stepper("Día de pago", value: viewModel.dueDay) { viewModel.stepDue(by: $0) }
            }
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
    }

    private var debtCurrency: String {
        viewModel.debtMode == .second ? viewModel.second ?? viewModel.principal : viewModel.principal
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
                stepButton("−", label: "Menos") { step(-1) }
                Text("\(value)")
                    .font(KWTextStyle.heading.font)
                    .monospacedDigit()
                    .frame(width: 28)
                stepButton("+", label: "Más") { step(1) }
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
