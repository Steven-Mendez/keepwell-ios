import AccountsDomain
import Core
import DesignSystem
import SharedPresentation
import SwiftUI

/// "Reconcile cash": the person types what they counted; the difference becomes a movement.
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
                Text("Reconcile cash", bundle: #bundle).kwTextStyle(.titleSm)
                KWGroupedCard {
                    KWValueRow(String(localized: "According to the app", bundle: #bundle), value: formatter.string(cash.balance))
                    SheetAmountRow(label: countedLabel, text: $countedText)
                }
                Text("If there's a difference, we record it as an adjustment so the balance matches.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.muted)
                SheetError(message: viewModel.actionError)
                Spacer(minLength: 0)
                Button {
                    isSaving = true
                    Task {
                        if await viewModel.reconcile(cash, countedText: countedText) {
                            onClose()
                        }
                        isSaving = false
                    }
                } label: {
                    Text("Reconcile", bundle: #bundle)
                }
                .buttonStyle(.kw())
                .disabled(isSaving || countedText.isEmpty)
            }
        }
        .onDisappear { viewModel.clearActionError() }
    }

    private var countedLabel: String {
        let currency = cash.balance.currency
        return String(localized: "What you have (\(currency))", bundle: #bundle)
    }
}

/// "ATM withdrawal": money taken from a bank account into cash.
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
                Text("ATM withdrawal", bundle: #bundle).kwTextStyle(.titleSm)
                KWFlowLayout {
                    ForEach(sources) { source in
                        KWChip(CardDisplay.name(of: source.account), isSelected: selectedSource == source.id) { sourceID = source.id }
                    }
                }
                KWGroupedCard {
                    SheetAmountRow(label: withdrawnLabel, text: $amountText)
                    if cash.balance.currency != principal {
                        SheetAmountRow(
                            label: debitedLabel,
                            hint: String(localized: "Optional · if it used another rate", bundle: #bundle),
                            text: $debitedText,
                        )
                    }
                }
                SheetError(message: viewModel.actionError)
                Spacer(minLength: 0)
                Button {
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
                } label: {
                    Text("Save withdrawal", bundle: #bundle)
                }
                .buttonStyle(.kw())
                .disabled(isSaving || amountText.isEmpty || selectedSource == nil)
            }
        }
        .onDisappear { viewModel.clearActionError() }
    }

    private var withdrawnLabel: String {
        let currency = cash.balance.currency
        return String(localized: "You withdrew (\(currency))", bundle: #bundle)
    }

    private var debitedLabel: String {
        String(localized: "\(principal) the bank charged you", bundle: #bundle)
    }

    private var selectedSource: UUID? {
        sourceID ?? sources.first?.id
    }
}

/// Label on the left, compact amount field on the right, as in the review step's "USD the
/// bank charged you".
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
            TextField(text: $text) { Text(verbatim: "0.00") }
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
