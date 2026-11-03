import SwiftUI

/// "Bank · [Bank name]": label left, input right, for rows inside a `KWGroupedCard`. Every input
/// sits on a filled `surface2` field so it reads as editable next to read-only `KWValueRow`s,
/// which use the same trailing alignment.
public struct KWTextFieldRow: View {
    private let label: String
    private let placeholder: String
    @Binding private var text: String
    private let keyboard: UIKeyboardType
    private let digitLimit: Int?
    private let width: CGFloat

    /// `digitLimit` keeps only that many digits ("last 4"), also when pasted. The row trims the
    /// text itself: a binding that trims in its setter leaves the extra digits on screen, since
    /// the stored value does not change and the field is not redrawn.
    public init(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        digitLimit: Int? = nil,
        width: CGFloat = 170,
    ) {
        self.label = label
        self.placeholder = placeholder
        _text = text
        self.keyboard = digitLimit == nil ? keyboard : .numberPad
        self.digitLimit = digitLimit
        self.width = width
    }

    public var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label)
                .foregroundStyle(KWColor.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(KWColor.Text.faint))
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(Text(label))
                .font(.kw(15, weight: 600))
                .frame(minHeight: KWInputMetrics.height)
                .kwInputField()
                .frame(maxWidth: width)
                .onChange(of: text) { _, new in
                    if let digitLimit {
                        let digits = Self.digits(new, limit: digitLimit)
                        if digits != new {
                            text = digits
                        }
                    }
                }
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.xs)
    }

    static func digits(_ text: String, limit: Int) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(limit))
    }
}

/// "Today's balance · [$ 0.00]": decimal pad with the currency symbol inside the field, as
/// Revolut writes "US$0", so people see which currency they type in before saving.
public struct KWAmountFieldRow: View {
    private let label: String
    private let hint: String?
    private let symbol: String?
    private let placeholder: String
    @Binding private var text: String
    private let width: CGFloat

    public init(
        _ label: String,
        hint: String? = nil,
        symbol: String? = nil,
        placeholder: String = "0.00",
        text: Binding<String>,
        width: CGFloat = 140,
    ) {
        self.label = label
        self.hint = hint
        self.symbol = symbol
        self.placeholder = placeholder
        _text = text
        self.width = width
    }

    public var body: some View {
        HStack(spacing: KWSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(KWColor.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(KWTextStyle.captionSm.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                if let symbol {
                    Text(symbol.trimmingCharacters(in: .whitespaces))
                        .foregroundStyle(KWColor.Text.muted)
                        .accessibilityHidden(true)
                }
                TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(KWColor.Text.faint))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(Text(label))
                    .monospacedDigit()
                    .frame(minHeight: KWInputMetrics.height)
            }
            .font(.kw(15, weight: 600))
            .kwInputField()
            .frame(maxWidth: width)
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.xs)
    }
}

enum KWInputMetrics {
    /// The text field itself spans the whole filled field: the keyboard scrolls the field's own
    /// frame into view, and a shorter one left the field's lower half under the form's footer.
    static let height = KWLayout.minTouch - 8
}

extension View {
    /// The filled look of every input: `surface2`, 10pt corners, at least a 44pt touch target.
    public func kwInputField() -> some View {
        padding(.horizontal, 10)
            .frame(minHeight: KWInputMetrics.height)
            .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}
