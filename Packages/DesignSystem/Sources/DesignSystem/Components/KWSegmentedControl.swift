import SwiftUI

/// Single-choice segmented control in the three looks the screens use.
public struct KWSegmentedControl<Value: Hashable>: View {
    public enum Style: Sendable {
        /// Equal-width segments, 38pt, white selection: "Gasto / Ingreso / Transferir".
        case large
        /// Hugging 30pt segments, white selection: "Gastos / Ingresos" in the summary header.
        case compact
        /// Hugging 30pt segments, accent selection: the currency switch under an amount.
        case accent
    }

    private let options: [(value: Value, title: String)]
    @Binding private var selection: Value
    private let style: Style

    public init(_ options: [(value: Value, title: String)], selection: Binding<Value>, style: Style = .large) {
        self.options = options
        _selection = selection
        self.style = style
    }

    public var body: some View {
        HStack(spacing: style == .accent ? 6 : KWSpacing.xxs) {
            ForEach(options, id: \.value) { option in
                segment(option)
            }
        }
        .padding(KWSpacing.xxs)
        .background(KWColor.Surface.surface, in: Capsule())
    }

    private func segment(_ option: (value: Value, title: String)) -> some View {
        let isSelected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(font)
                .lineLimit(1)
                .foregroundStyle(isSelected ? selectedForeground : KWColor.Text.secondary)
                .padding(.horizontal, style == .large ? 0 : horizontalPadding)
                .frame(maxWidth: style == .large ? .infinity : nil)
                .frame(height: style == .large ? 38 : 30)
                .background(isSelected ? selectedBackground : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var font: Font {
        switch style {
        case .large: KWTextStyle.label.font
        case .compact: .kw(13, weight: 600, relativeTo: .footnote)
        case .accent: .kw(13, weight: 700, relativeTo: .footnote)
        }
    }

    private var horizontalPadding: CGFloat {
        style == .accent ? 14 : KWSpacing.sm
    }

    private var selectedBackground: Color {
        style == .accent ? KWColor.Brand.accent : .white
    }

    private var selectedForeground: Color {
        style == .accent ? KWColor.Text.primary : .black
    }
}

#Preview {
    @Previewable @State var kind = "gasto"
    @Previewable @State var view = 0
    @Previewable @State var currency = "NIO"
    VStack(spacing: KWSpacing.md) {
        KWSegmentedControl(
            [(value: "gasto", title: "Gasto"), (value: "ingreso", title: "Ingreso"), (value: "transfer", title: "Transferir")],
            selection: $kind,
        )
        KWSegmentedControl([(value: 0, title: "Gastos"), (value: 1, title: "Ingresos")], selection: $view, style: .compact)
        KWSegmentedControl([(value: "NIO", title: "NIO"), (value: "USD", title: "USD")], selection: $currency, style: .accent)
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
