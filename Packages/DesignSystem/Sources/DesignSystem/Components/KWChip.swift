import SwiftUI

/// Selectable pill. `filled` is the list filter chip, `outlined` the currency chooser and `extra`
/// the lima chip for a highlighted choice.
public struct KWChip: View {
    public enum Style: Sendable {
        case filled
        case outlined
        case extra
    }

    private let title: String
    private let isSelected: Bool
    private let style: Style
    private let height: CGFloat
    private let action: () -> Void

    public init(
        _ title: String,
        isSelected: Bool,
        style: Style = .filled,
        height: CGFloat = KWComponentMetrics.chipHeight,
        action: @escaping () -> Void,
    ) {
        self.title = title
        self.isSelected = isSelected
        self.style = style
        self.height = height
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(KWTextStyle.label.font)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, style == .filled ? KWSpacing.md : 14)
                .frame(height: height)
                .background(background, in: Capsule())
                .overlay {
                    if let border {
                        Capsule().inset(by: 0.5).stroke(border, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        switch style {
        case .filled, .outlined: isSelected ? KWColor.Semantic.primaryForeground : KWColor.Text.secondary
        case .extra: isSelected ? KWColor.State.extra : KWColor.Text.secondary
        }
    }

    private var background: Color {
        switch style {
        case .filled, .outlined: isSelected ? KWColor.Semantic.primary : KWColor.Surface.surface
        case .extra: isSelected ? KWColor.Tint.extra : KWColor.Surface.surface
        }
    }

    private var border: Color? {
        switch style {
        case .filled: nil
        case .outlined: isSelected ? KWColor.Semantic.primary : KWColor.Surface.border
        case .extra: isSelected ? KWColor.State.extra : KWColor.Surface.border
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: KWSpacing.sm) {
        HStack(spacing: KWSpacing.xs) {
            KWChip("All", isSelected: true) {}
            KWChip("Expenses", isSelected: false) {}
        }
        HStack(spacing: KWSpacing.xs) {
            KWChip("NIO · Córdoba", isSelected: true, style: .outlined, height: 38) {}
            KWChip("EUR · Euro", isSelected: false, style: .outlined, height: 38) {}
        }
        HStack(spacing: KWSpacing.xs) {
            KWChip("Groceries", isSelected: true, style: .extra) {}
            KWChip("Shopping", isSelected: false, style: .extra) {}
        }
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
