import DesignSystem
import Domain
import SwiftUI

// Pieces both card screens (credit and debit) are built from, so a card reads and edits the same
// way whichever kind it is.

/// The card big at the top, with its nickname and a line under it, as banks show "my card".
public struct CardHero: View {
    private let art: KWCardArt
    private let name: String
    private let subtitle: String?

    public init(art: KWCardArt, name: String, subtitle: String? = nil) {
        self.art = art
        self.name = name
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: KWSpacing.md) {
            art
            VStack(spacing: KWSpacing.xxs) {
                Text(name)
                    .kwTextStyle(.titleSm)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(KWTextStyle.label.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.onBrand)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, KWSpacing.xs)
        }
    }
}

/// One row of a card's "Manage card" list: a round icon, a title, an optional value and a chevron.
public struct CardManageRow: View {
    private let title: String
    private let icon: KWIcon
    private let value: String?
    private let isDestructive: Bool
    private let action: () -> Void

    public init(_ title: String, icon: KWIcon, value: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.value = value
        self.isDestructive = isDestructive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: KWSpacing.sm) {
                KWIconView(icon, size: 18)
                    .frame(width: 36, height: 36)
                    .background(isDestructive ? KWColor.State.negative.opacity(0.16) : KWColor.Surface.surface2, in: Circle())
                Text(title)
                    .font(.kw(15, weight: 600))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value)
                        .font(KWTextStyle.label.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                }
                if !isDestructive {
                    KWIconView(.chevronRight, size: 16)
                        .foregroundStyle(KWColor.Text.faint)
                }
            }
            .foregroundStyle(isDestructive ? KWColor.State.negative : KWColor.Text.primary)
            .padding(.vertical, KWSpacing.sm)
            .frame(minHeight: KWLayout.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Renames the account a card belongs to.
public struct CardNameSheet: View {
    private let errorMessage: String?
    private let isSaving: Bool
    private let onSave: (String) async -> Bool
    private let onClose: () -> Void
    @State private var name: String

    /// `onSave` returns whether the sheet can close.
    public init(
        name: String,
        errorMessage: String?,
        isSaving: Bool,
        onSave: @escaping (String) async -> Bool,
        onClose: @escaping () -> Void,
    ) {
        _name = State(initialValue: name)
        self.errorMessage = errorMessage
        self.isSaving = isSaving
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("Edit name", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                KWGroupedCard {
                    TextField(String(localized: "Account name", bundle: #bundle), text: $name)
                        .font(.kw(17, weight: 600))
                        .submitLabel(.done)
                        .onSubmit(save)
                        .padding(.vertical, KWSpacing.md)
                }
                Text("Every card on this account shows this name.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                if let errorMessage {
                    Text(errorMessage)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
                Spacer(minLength: 0)
                Button(action: save) { Text("Save", bundle: #bundle) }
                    .buttonStyle(.kw())
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        KWKeyboard.dismiss()
        Task {
            if await onSave(name) {
                onClose()
            }
        }
    }
}

/// What's printed on the plastic besides its digits: the product name and the "valid thru".
public struct CardDetailsSheet: View {
    private let errorMessage: String?
    private let isSaving: Bool
    private let onSave: (String?, CardExpiry?) async -> Bool
    private let onClose: () -> Void
    private let years: [Int]
    @State private var productName: String
    @State private var month: Int?
    @State private var year: Int?

    /// `onSave` returns whether the sheet can close.
    public init(
        card: Card,
        errorMessage: String?,
        isSaving: Bool,
        now: Date = .now,
        calendar: Calendar = .current,
        onSave: @escaping (String?, CardExpiry?) async -> Bool,
        onClose: @escaping () -> Void,
    ) {
        _productName = State(initialValue: card.productName ?? "")
        _month = State(initialValue: card.expiry?.month)
        _year = State(initialValue: card.expiry?.year)
        // Plastics last up to about ten years; an already expired one can still be recorded.
        let thisYear = calendar.component(.year, from: now)
        years = Array(Set((thisYear - 1 ... thisYear + 10).map(\.self) + [card.expiry?.year].compactMap(\.self))).sorted()
        self.errorMessage = errorMessage
        self.isSaving = isSaving
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("Product and expiry", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                KWGroupedCard {
                    TextField(String(localized: "Product name (e.g. Platinum)", bundle: #bundle), text: $productName)
                        .font(.kw(17, weight: 600))
                        .submitLabel(.done)
                        .padding(.vertical, KWSpacing.md)
                    picker(String(localized: "Expiry month", bundle: #bundle), selection: $month, options: Array(1 ... 12)) {
                        String(format: "%02d", $0)
                    }
                    picker(String(localized: "Expiry year", bundle: #bundle), selection: $year, options: years) { String($0) }
                }
                Text("As printed on the card. We remind you a month before it expires, with what's charged to it.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                if let message = isIncomplete ? String(localized: "Choose both the month and the year.", bundle: #bundle) : errorMessage {
                    Text(message)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
                Spacer(minLength: 0)
                Button(action: save) { Text("Save", bundle: #bundle) }
                    .buttonStyle(.kw())
                    .disabled(isSaving || isIncomplete)
            }
        }
    }

    /// Only one half of the expiry chosen.
    private var isIncomplete: Bool {
        (month == nil) != (year == nil)
    }

    private func picker(_ label: String, selection: Binding<Int?>, options: [Int], title: @escaping (Int) -> String) -> some View {
        let notSet = String(localized: "Not set", bundle: #bundle)
        return Menu {
            Button { selection.wrappedValue = nil } label: { Text(notSet) }
            ForEach(options, id: \.self) { option in
                Button(title(option)) { selection.wrappedValue = option }
            }
        } label: {
            KWValueRow(
                label,
                value: (selection.wrappedValue.map(title) ?? notSet) + " ›",
                style: selection.wrappedValue == nil ? .placeholder : .detail,
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        KWKeyboard.dismiss()
        let expiry = month.flatMap { month in year.flatMap { try? CardExpiry(month: month, year: $0) } }
        Task {
            if await onSave(productName, expiry) {
                onClose()
            }
        }
    }
}

/// Picks a card's color with a live preview of the art.
public struct CardColorSheet: View {
    private let preview: (CardColor) -> KWCardArt
    private let onSave: (CardColor) async -> Bool
    private let onClose: () -> Void
    @State private var color: CardColor
    private let colors: [CardColor]

    /// `onSave` returns whether the sheet can close.
    public init(
        color: CardColor?,
        preview: @escaping (CardColor) -> KWCardArt,
        onSave: @escaping (CardColor) async -> Bool,
        onClose: @escaping () -> Void,
    ) {
        _color = State(initialValue: color ?? .azul)
        colors = CardDisplay.selectableColors(keeping: color)
        self.preview = preview
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.lg) {
                KWFlowHeader(.close, action: onClose)
                Text("Card color", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                preview(color)
                    .animation(.snappy, value: color)
                swatches
                Spacer(minLength: 0)
                Button {
                    Task {
                        if await onSave(color) {
                            onClose()
                        }
                    }
                } label: {
                    Text("Save", bundle: #bundle)
                }
                .buttonStyle(.kw())
            }
        }
    }

    private var swatches: some View {
        HStack(spacing: KWSpacing.xxs) {
            ForEach(colors, id: \.self) { option in
                let palette = CardDisplay.palette(for: option)
                Button { color = option } label: {
                    Circle()
                        .fill(palette.largeGradient)
                        // Keeps the black swatch from disappearing into the black sheet.
                        .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                        .frame(width: 32, height: 32)
                        .overlay { Circle().strokeBorder(.white, lineWidth: color == option ? 2 : 0).padding(-4) }
                        .frame(width: KWLayout.minTouch, height: KWLayout.minTouch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(palette.displayName)
                .accessibilityAddTraits(color == option ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
