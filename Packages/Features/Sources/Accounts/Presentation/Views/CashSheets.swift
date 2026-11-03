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
    @FocusState private var isCounting: Bool

    var body: some View {
        KWFormScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("Reconcile cash", bundle: #bundle).kwTextStyle(.titleSm)
                KWGroupedCard {
                    KWValueRow(String(localized: "According to the app", bundle: #bundle), value: formatter.string(cash.balance))
                    KWAmountFieldRow(
                        countedLabel,
                        symbol: CurrencyFormatter.symbol(for: cash.balance.currency),
                        text: $countedText,
                    )
                    .focused($isCounting)
                }
                Text("If there's a difference, we record it as an adjustment so the balance matches.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.muted)
                SheetError(message: viewModel.actionError)
            }
        } footer: {
            Button {
                isCounting = false
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
        // Counting is the only thing to do here, so the pad opens with the sheet.
        .onAppear { isCounting = true }
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
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case withdrawn
        case debited
    }

    var body: some View {
        KWFormScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("ATM withdrawal", bundle: #bundle).kwTextStyle(.titleSm)
                KWFlowLayout {
                    ForEach(sources) { source in
                        KWChip(CardDisplay.name(of: source.account), isSelected: selectedSource == source.id) { sourceID = source.id }
                    }
                }
                KWGroupedCard {
                    KWAmountFieldRow(withdrawnLabel, symbol: CurrencyFormatter.symbol(for: cash.balance.currency), text: $amountText)
                        .kwFocused($focus, equals: .withdrawn)
                    if cash.balance.currency != principal {
                        KWAmountFieldRow(
                            debitedLabel,
                            hint: String(localized: "Optional · if it used another rate", bundle: #bundle),
                            symbol: CurrencyFormatter.symbol(for: principal),
                            text: $debitedText,
                        )
                        .kwFocused($focus, equals: .debited)
                    }
                }
                SheetError(message: viewModel.actionError)
            }
        } footer: {
            Button {
                guard let source = selectedSource else { return }
                focus = nil
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
        .kwKeyboardToolbar($focus, order: cash.balance.currency != principal ? [.withdrawn, .debited] : [.withdrawn])
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
