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
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("sheet.cardDetails", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                KWGroupedCard {
                    SheetAmountField(
                        label: String(localized: "Credit limit (\(detail.limitCurrency))", bundle: #bundle),
                        placeholder: String(localized: "Optional", bundle: #bundle),
                        text: $limitText,
                    )
                    dayRow(String(localized: "Cutoff day", bundle: #bundle), selection: $cutoffDay)
                    dayRow(String(localized: "Payment day", bundle: #bundle), selection: $dueDay)
                }
                Text("With the cutoff day, additional cards count their cap per cycle and we remind you before paying.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                SheetError(message: viewModel.errorMessage)
                Spacer(minLength: 0)
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

/// A new additional card: who carries it, its digits, art and cycle cap.
struct NewAdditionalSheet: View {
    let viewModel: CreditCardViewModel
    /// The new card's id, or `nil` when closed without adding.
    let onFinish: (UUID?) -> Void
    @State private var holderName = ""
    @State private var lastFour = ""
    @State private var color = CardColor.lima
    @State private var capText = ""

    private static let colors: [CardColor] = [.lima, .azul, .verde, .violeta, .coral, .oro, .grafito]

    var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close) { onFinish(nil) }
                Text("New additional card", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                preview
                colorPicker
                fields
                SheetError(message: viewModel.errorMessage)
                Spacer(minLength: 0)
                Button {
                    KWKeyboard.dismiss()
                    Task {
                        if let id = await viewModel.createAdditional(
                            holderName: holderName,
                            lastFour: lastFour,
                            color: color,
                            capText: capText,
                        ) {
                            onFinish(id)
                        }
                    }
                } label: {
                    Text("Add card", bundle: #bundle)
                }
                .buttonStyle(.kw())
                .disabled(viewModel.isSaving || holderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var fields: some View {
        KWGroupedCard {
            SheetTextField(
                label: String(localized: "Who carries it", bundle: #bundle),
                placeholder: String(localized: "Family", bundle: #bundle),
                text: $holderName,
            )
            SheetTextField(
                label: String(localized: "Last 4 digits", bundle: #bundle),
                placeholder: String(localized: "Optional", bundle: #bundle),
                text: $lastFour,
                isNumeric: true,
            )
            SheetAmountField(
                label: String(localized: "Cap per cycle (\(viewModel.detail?.capCurrency ?? ""))", bundle: #bundle),
                placeholder: String(localized: "No cap", bundle: #bundle),
                text: $capText,
            )
        }
    }

    private var preview: some View {
        KWCardArt(
            palette: CardDisplay.palette(for: color),
            bank: viewModel.detail.map(viewModel.bank) ?? "",
            badge: .tag(String(localized: "Additional", bundle: #bundle)),
            caption: holderName.isEmpty ? nil : holderName,
            lastFour: lastFour.isEmpty ? nil : lastFour,
            network: CardDisplay.wordmark(for: viewModel.detail?.holder?.network),
            showsShadow: false,
        )
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
    }

    private var colorPicker: some View {
        HStack(spacing: KWSpacing.xxs) {
            ForEach(Self.colors, id: \.self) { option in
                Button { color = option } label: {
                    Circle()
                        .fill(CardDisplay.palette(for: option).gradient)
                        .frame(width: 30, height: 30)
                        .overlay { Circle().strokeBorder(.white, lineWidth: color == option ? 2 : 0).padding(-4) }
                        .frame(width: KWLayout.minTouch, height: KWLayout.minTouch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CardDisplay.palette(for: option).displayName)
                .accessibilityAddTraits(color == option ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Form rows

struct SheetTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isNumeric = false

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label).foregroundStyle(KWColor.Text.secondary)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .keyboardType(isNumeric ? .numberPad : .default)
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.sm)
    }
}

struct SheetAmountField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label).foregroundStyle(KWColor.Text.secondary)
            Spacer(minLength: KWSpacing.xs)
            TextField(label, text: $text, prompt: Text(placeholder))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .monospacedDigit()
                .padding(.vertical, KWSpacing.xs)
                .padding(.horizontal, 10)
                .frame(width: 120)
                .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.sm)
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
