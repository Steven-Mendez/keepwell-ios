import DesignSystem
import Domain
import SwiftUI

/// Step 1 · Monto y tipo, with the app's own keypad.
public struct AmountView: View {
    @Bindable private var viewModel: CreateTransactionViewModel
    private let onClose: () -> Void

    public init(viewModel: CreateTransactionViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        KWScreen(bottom: 34) {
            VStack(spacing: KWSpacing.md) {
                KWFlowHeader(.close, progress: (4, 1), action: onClose)
                KWSegmentedControl(
                    [
                        (value: TransactionKind.expense, title: "Gasto"),
                        (value: .income, title: "Ingreso"),
                        (value: .transfer, title: "Transferir"),
                    ],
                    selection: Binding(get: { viewModel.kind }, set: { viewModel.setKind($0) }),
                )
                VStack(spacing: KWSpacing.sm) {
                    Text(viewModel.amountDisplay)
                        .font(.kw(52, weight: 800, relativeTo: .largeTitle))
                        .tracking(-2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Monto \(viewModel.amountDisplay)")
                    if viewModel.currencyOptions.count > 1 {
                        KWSegmentedControl(
                            viewModel.currencyOptions.map { (value: $0, title: $0) },
                            selection: $viewModel.currency,
                            style: .accent,
                        )
                    }
                    if let conversion = viewModel.conversionLine {
                        Text(conversion)
                            .font(KWTextStyle.label.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                            .monospacedDigit()
                    }
                }
                .frame(maxHeight: .infinity)
                keypad
                Button("Siguiente") { viewModel.continueFromAmount() }
                    .buttonStyle(.kw())
                    .disabled(!viewModel.canContinueFromAmount)
            }
        }
        .task {
            if viewModel.context == nil {
                await viewModel.load()
            }
        }
    }

    private var keypad: some View {
        let keys: [CreateTransactionViewModel.Key] = (1 ... 9).map { .digit($0) } + [.dot, .digit(0), .delete]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: KWSpacing.xs), count: 3), spacing: KWSpacing.xs) {
            ForEach(keys, id: \.self) { key in
                Button { viewModel.press(key) } label: {
                    Text(label(key))
                        .font(.kw(26, weight: 600))
                        .foregroundStyle(KWColor.Text.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWSpacing.md))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key == .delete ? "Borrar" : label(key))
            }
        }
    }

    private func label(_ key: CreateTransactionViewModel.Key) -> String {
        switch key {
        case let .digit(value): "\(value)"
        case .dot: "."
        case .delete: "⌫"
        }
    }
}
