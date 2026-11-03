import SwiftUI

/// "Label … value" row. `prominent` is the settings look (white label, semibold value); the
/// default is the detail look (secondary label).
public struct KWValueRow: View {
    public enum Style: Sendable {
        /// Secondary label, semibold white value: "Estado · Confirmado".
        case detail
        /// Secondary label, faint value: "Límite de crédito · Sin definir".
        case placeholder
        /// White label, semibold value: settings rows.
        case setting
        /// White label, muted value: navigation rows with a count ("15 ›").
        case navigation
    }

    private let label: String
    private let value: String
    private let style: Style
    private let valueColor: Color?
    private let verticalPadding: CGFloat

    public init(_ label: String, value: String, style: Style = .detail, valueColor: Color? = nil, verticalPadding: CGFloat = 13) {
        self.label = label
        self.value = value
        self.style = style
        self.valueColor = valueColor
        self.verticalPadding = verticalPadding
    }

    public var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label)
                .foregroundStyle(style == .setting || style == .navigation ? KWColor.Text.primary : KWColor.Text.secondary)
            Spacer(minLength: KWSpacing.xs)
            Text(value)
                .font(.kw(15, weight: style == .detail || style == .setting ? 600 : 400))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? defaultValueColor)
                .multilineTextAlignment(.trailing)
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, verticalPadding)
        .accessibilityElement(children: .combine)
    }

    private var defaultValueColor: Color {
        switch style {
        case .detail, .setting: KWColor.Text.primary
        case .placeholder: KWColor.Text.faint
        case .navigation: KWColor.Text.muted
        }
    }
}

/// Title with a smaller subtitle under it, the leading block of most rows.
public struct KWTitleSubtitle: View {
    private let title: String
    private let subtitle: String?
    private let titleFont: Font
    private let spacing: CGFloat

    public init(_ title: String, subtitle: String? = nil, titleFont: Font = .kw(15, weight: 600), spacing: CGFloat = 2) {
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.spacing = spacing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(KWColor.Text.primary)
            if let subtitle {
                Text(subtitle)
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.muted)
            }
        }
        .lineLimit(1)
    }
}

/// Section titles above cards. `small` is the muted 14pt label ("Moneda"), `large` the 17pt
/// heading ("Tarjetas de crédito") with an optional trailing accessory.
public struct KWSectionHeader<Accessory: View>: View {
    public enum Style: Sendable {
        case small
        case large
    }

    private let title: String
    private let style: Style
    private let accessory: Accessory

    public init(_ title: String, style: Style = .small, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.style = style
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(style == .small ? KWTextStyle.label.font : KWTextStyle.heading.font)
                .foregroundStyle(style == .small ? KWColor.Text.muted : KWColor.Text.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: KWSpacing.xs)
            accessory
        }
    }
}

extension KWSectionHeader where Accessory == EmptyView {
    public init(_ title: String, style: Style = .small) {
        self.init(title, style: style) { EmptyView() }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: KWSpacing.xs) {
        KWSectionHeader("Moneda")
        KWGroupedCard {
            KWValueRow("Moneda principal", value: "USD · Dólar ›", style: .setting, verticalPadding: 14)
            KWValueRow("Categorías de gasto", value: "15 ›", style: .navigation, verticalPadding: 14)
        }
        KWSectionHeader("Plásticos", style: .large) {
            Text("+ Adicional").font(KWTextStyle.label.font).foregroundStyle(KWColor.Brand.link)
        }
        KWGroupedCard(verticalPadding: 4) {
            KWValueRow("Límite de crédito", value: "Sin definir", style: .placeholder)
            KWValueRow("Estado", value: "Confirmado", valueColor: KWColor.State.positive)
        }
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
