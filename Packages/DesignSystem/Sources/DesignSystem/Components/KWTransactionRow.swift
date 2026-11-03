import SwiftUI

/// Visual kind of a movement row. Planned wins over the movement type because the design
/// shows every planned movement in amber regardless of direction.
public enum KWTransactionStyle: Sendable {
    case expense
    case income
    case transfer
    case planned

    var icon: KWIcon {
        switch self {
        case .expense: .arrowUpRight
        case .income: .arrowDownLeft
        case .transfer: .transfer
        case .planned: .clock
        }
    }

    var iconBackground: Color {
        switch self {
        case .expense: KWColor.Surface.surface2
        case .income: KWColor.Tint.positive
        case .transfer: KWColor.Tint.accent
        case .planned: KWColor.Tint.pending
        }
    }

    var iconForeground: Color {
        switch self {
        case .expense: KWColor.Text.secondary
        case .income: KWColor.State.positive
        case .transfer: KWColor.State.transfer
        case .planned: KWColor.State.pending
        }
    }

    var amountColor: Color {
        switch self {
        case .expense: KWColor.Text.primary
        case .income: KWColor.State.positive
        case .transfer: KWColor.State.transfer
        case .planned: KWColor.State.pending
        }
    }
}

/// 40pt tinted circle with the movement's icon.
public struct KWTransactionIcon: View {
    private let style: KWTransactionStyle

    public init(_ style: KWTransactionStyle) {
        self.style = style
    }

    public var body: some View {
        KWIconView(style.icon, size: 20)
            .foregroundStyle(style.iconForeground)
            .frame(width: 40, height: 40)
            .background(style.iconBackground, in: Circle())
    }
}

/// One movement: icon, title and subtitle, amount and its conversion. Amounts arrive formatted
/// because the sign and currency rules live outside the design system.
public struct KWTransactionRow<Trailing: View>: View {
    private let style: KWTransactionStyle
    private let title: String
    private let subtitle: String
    private let trailing: Trailing

    public init(_ style: KWTransactionStyle, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.style = style
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: KWSpacing.sm) {
            KWTransactionIcon(style)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.kw(15, weight: 600))
                    .foregroundStyle(KWColor.Text.primary)
                Text(subtitle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, KWSpacing.sm)
    }
}

extension KWTransactionRow where Trailing == KWTransactionAmounts {
    public init(_ style: KWTransactionStyle, title: String, subtitle: String, amount: String, secondaryAmount: String? = nil) {
        self.init(style, title: title, subtitle: subtitle) {
            KWTransactionAmounts(style, amount: amount, secondaryAmount: secondaryAmount)
        }
    }
}

/// Trailing amount column of a movement row.
public struct KWTransactionAmounts: View {
    private let style: KWTransactionStyle
    private let amount: String
    private let secondaryAmount: String?

    public init(_ style: KWTransactionStyle, amount: String, secondaryAmount: String?) {
        self.style = style
        self.amount = amount
        self.secondaryAmount = secondaryAmount
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(amount)
                .font(.kw(15, weight: 700))
                .foregroundStyle(style.amountColor)
            if let secondaryAmount {
                Text(secondaryAmount)
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.faint)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}

#Preview {
    KWGroupedCard(horizontalPadding: 14, verticalPadding: 4) {
        KWTransactionRow(.planned, title: "Renta", subtitle: "Vivienda · Débito 1234", amount: "−C$3,500.00", secondaryAmount: "≈ $95.56")
        KWTransactionRow(.expense, title: "Almuerzo", subtitle: "Restaurantes · Efectivo", amount: "−C$250.00", secondaryAmount: "$6.83")
        KWTransactionRow(
            .transfer,
            title: "Retiro",
            subtitle: "Ahorro → Efectivo",
            amount: "C$1,200.00",
            secondaryAmount: "$33.15 debitado",
        )
        KWTransactionRow(.income, title: "Intereses", subtitle: "Intereses · Ahorro", amount: "+$3.02", secondaryAmount: "C$110.61")
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
