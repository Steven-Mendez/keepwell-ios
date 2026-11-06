import Core
import CreditCardDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

// MARK: - Sheets

/// Credit limit, cutoff and due day.
struct TermsSheet: View {
    let viewModel: CreditCardViewModel
    let detail: CreditCardDetail
    let onClose: () -> Void
    @State private var limitText: String
    @State private var cutoffDay: Int?
    @State private var dueDay: Int?

    init(viewModel: CreditCardViewModel, detail: CreditCardDetail, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.detail = detail
        self.onClose = onClose
        let terms = detail.account.creditTerms
        _limitText = State(initialValue: terms?.limit
            .map { viewModel.formatter.number($0.amount).replacingOccurrences(of: ",", with: "") } ?? "")
        _cutoffDay = State(initialValue: terms?.cutoffDay)
        _dueDay = State(initialValue: terms?.dueDay)
    }

    var body: some View {
        KWFormScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("sheet.cardDetails", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                KWGroupedCard {
                    KWAmountFieldRow(
                        String(localized: "Credit limit (\(detail.limitCurrency))", bundle: #bundle),
                        symbol: CurrencyFormatter.symbol(for: detail.limitCurrency),
                        placeholder: String(localized: "Optional", bundle: #bundle),
                        text: $limitText,
                    )
                    dayRow(String(localized: "Cutoff day", bundle: #bundle), selection: $cutoffDay)
                    dayRow(String(localized: "Payment day", bundle: #bundle), selection: $dueDay)
                }
                Text("The cutoff day closes each cycle, and with the payment day we remind you before it's due.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                SheetError(message: viewModel.errorMessage)
            }
        } footer: {
            Button {
                KWKeyboard.dismiss()
                Task {
                    if await viewModel.saveTerms(limitText: limitText, cutoffDay: cutoffDay, dueDay: dueDay) {
                        onClose()
                    }
                }
            } label: {
                Text("Save", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(viewModel.isSaving)
        }
    }

    private func dayRow(_ label: String, selection: Binding<Int?>) -> some View {
        Menu {
            Button { selection.wrappedValue = nil } label: { Text("Not set", bundle: #bundle) }
            ForEach(1 ... 31, id: \.self) { day in
                Button("\(day)") { selection.wrappedValue = day }
            }
        } label: {
            KWValueRow(
                label,
                value: selection.wrappedValue.map { String(localized: "Day \($0)", bundle: #bundle) + " ›" } ?? String(
                    localized: "Not set",
                    bundle: #bundle,
                ) + " ›",
                style: selection.wrappedValue == nil ? .placeholder : .detail,
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Form rows

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
