import AccountsDomain
import Core
import DesignSystem
import SharedPresentation
import SwiftUI

/// "Cuadrar efectivo": the person types what they counted; the difference becomes a movement.
struct ReconcileCashSheet: View {
    let viewModel: AccountsViewModel
    let cash: AccountsOverview.Cash
    let formatter: CurrencyFormatter
    let onClose: () -> Void
    @State private var countedText = ""
    @State private var isSaving = false

    var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("Cuadrar efectivo").kwTextStyle(.titleSm)
                KWGroupedCard {
                    KWValueRow("Según la app", value: formatter.string(cash.balance))
                    SheetAmountRow(label: "Lo que tienes (\(cash.balance.currency))", text: $countedText)
                }
                Text("Si hay diferencia, la anotamos como un ajuste para que el saldo cuadre.")
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.muted)
                SheetError(message: viewModel.actionError)
                Spacer(minLength: 0)
                Button("Cuadrar") {
                    isSaving = true
                    Task {
                        if await viewModel.reconcile(cash, countedText: countedText) {
                            onClose()
                        }
                        isSaving = false
                    }
                }
                .buttonStyle(.kw())
                .disabled(isSaving || countedText.isEmpty)
            }
        }
        .onDisappear { viewModel.clearActionError() }
    }
}

/// "Retiro de cajero": money taken from a bank account into cash.
struct WithdrawCashSheet: View {
    let viewModel: AccountsViewModel
    let cash: AccountsOverview.Cash
    let sources: [AccountsOverview.Deposit]
    let principal: String
    let onClose: () -> Void
    @State private var sourceID: UUID?
    @State private var amountText = ""
    @State private var debitedText = ""
    @State private var isSaving = false

    var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("Retiro de cajero").kwTextStyle(.titleSm)
                KWFlowLayout {
                    ForEach(sources) { source in
                        KWChip(CardDisplay.name(of: source.account), isSelected: selectedSource == source.id) { sourceID = source.id }
                    }
                }
                KWGroupedCard {
                    SheetAmountRow(label: "Retiraste (\(cash.balance.currency))", text: $amountText)
                    if cash.balance.currency != principal {
                        SheetAmountRow(label: "\(principal) que te cobró el banco", hint: "Opcional · si usó otra tasa", text: $debitedText)
                    }
                }
                SheetError(message: viewModel.actionError)
                Spacer(minLength: 0)
                Button("Guardar retiro") {
                    guard let source = selectedSource else { return }
                    isSaving = true
                    Task {
                        if await viewModel
                            .withdraw(into: cash, from: source, amountText: amountText, debitedText: debitedText)
                        {
                            onClose()
                        }
                        isSaving = false
                    }
                }
                .buttonStyle(.kw())
                .disabled(isSaving || amountText.isEmpty || selectedSource == nil)
            }
        }
        .onDisappear { viewModel.clearActionError() }
    }

    private var selectedSource: UUID? {
        sourceID ?? sources.first?.id
    }
}

/// Label on the left, compact amount field on the right, as in the review step's "USD que te
/// cobró el banco".
struct SheetAmountRow: View {
    let label: String
    var hint: String?
    @Binding var text: String

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(KWColor.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
                }
            }
            Spacer()
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .monospacedDigit()
                .padding(.vertical, KWSpacing.xs)
                .padding(.horizontal, 10)
                .frame(width: 100)
                .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, 11)
    }
}

struct SheetError: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.State.negative)
        }
    }
}
