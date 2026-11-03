import DesignSystem
import SwiftUI

/// "Banco · Banpro": label left, borderless input right, as in the plastic step.
struct FormTextRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 150
    var numeric = false

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label).foregroundStyle(KWColor.Text.secondary)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .keyboardType(numeric ? .numberPad : .default)
                .frame(width: width)
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.sm)
    }
}

/// "Deuda en USD · [0.00]": label left, filled amount field right.
struct FormAmountRow: View {
    let label: String
    @Binding var text: String
    var placeholder = "0.00"
    var filled = true

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label).foregroundStyle(KWColor.Text.secondary)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .monospacedDigit()
                .padding(.vertical, filled ? KWSpacing.xs : 0)
                .padding(.horizontal, filled ? 10 : 0)
                .frame(width: filled ? 100 : 120)
                .background(filled ? KWColor.Surface.surface2 : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.sm)
    }
}
