import SwiftUI

/// Pill buttons. Variants and sizes mirror the combinations the screens use, so call sites pick
/// a role instead of restating colors, heights and fonts.
public struct KWButtonStyle: ButtonStyle {
    public enum Variant: Sendable {
        /// White fill, black label: the main action of a screen.
        case primary
        /// `surface2` fill.
        case secondary
        /// `surface` fill, as "Log another".
        case surface
        /// `surface` fill with the negative color: "Delete account", "Eliminar todos mis datos".
        case destructive
        /// `surface2` fill with the link color: "Complete card details".
        case link
        /// No fill, white label: "Not now", "Ir al inicio".
        case plain
    }

    public enum Size: Sendable {
        /// 54pt, heading. Primary and secondary screen actions.
        case large
        /// 52pt, heading. Paired actions and the lock screen.
        case regular
        /// 50pt, 15/600. Full-width destructive rows.
        case row
        /// 44pt, 15/600. Text-only secondary actions.
        case text
        /// 40pt, 14/700. Inline card actions ("Reconcile").
        case medium
        /// 34pt, 14/600. Compact actions ("Back up now").
        case small
        /// 32pt, 13/600. Row actions ("Confirm").
        case mini

        var height: CGFloat {
            switch self {
            case .large: KWComponentMetrics.buttonHeight
            case .regular: 52
            case .row: 50
            case .text: KWLayout.minTouch
            case .medium: 40
            case .small: 34
            case .mini: 32
            }
        }

        var font: Font {
            switch self {
            case .large, .regular: KWTextStyle.heading.font
            case .row, .text: .kw(15, weight: 600)
            case .medium: .kw(14, weight: 700, relativeTo: .subheadline)
            case .small: .kw(14, weight: 600, relativeTo: .subheadline)
            case .mini: .kw(13, weight: 600, relativeTo: .footnote)
            }
        }

        /// Compact sizes hug their label; the rest stretch to the available width.
        var fillsWidth: Bool {
            switch self {
            case .large, .regular, .row, .text, .medium: true
            case .small, .mini: false
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: 14
            case .mini: 12
            default: KWSpacing.md
            }
        }
    }

    private let variant: Variant
    private let size: Size
    private let height: CGFloat?

    /// `height` overrides the size's height for the few text buttons drawn taller or shorter.
    public init(_ variant: Variant = .primary, size: Size = .large, height: CGFloat? = nil) {
        self.variant = variant
        self.size = size
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: size.fillsWidth ? .infinity : nil)
            .frame(height: height ?? size.height)
            .background(background, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .modifier(DisabledDimming())
    }

    private var foreground: Color {
        switch variant {
        case .primary: KWColor.Semantic.primaryForeground
        case .secondary, .surface, .plain: KWColor.Text.primary
        case .destructive: KWColor.State.negative
        case .link: KWColor.Brand.link
        }
    }

    private var background: Color {
        switch variant {
        case .primary: KWColor.Semantic.primary
        case .secondary, .link: KWColor.Surface.surface2
        case .surface, .destructive: KWColor.Surface.surface
        case .plain: .clear
        }
    }
}

private struct DisabledDimming: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == KWButtonStyle {
    public static func kw(_ variant: KWButtonStyle.Variant = .primary, size: KWButtonStyle.Size = .large) -> KWButtonStyle {
        KWButtonStyle(variant, size: size)
    }
}

#Preview {
    VStack(spacing: KWSpacing.sm) {
        Button("Continue") {}.buttonStyle(.kw())
        Button("ATM withdrawal") {}.buttonStyle(.kw(.secondary))
        Button("Log another") {}.buttonStyle(.kw(.surface, size: .regular))
        Button("Delete account") {}.buttonStyle(.kw(.destructive, size: .row))
        Button("Complete card details") {}.buttonStyle(.kw(.link, size: .medium))
        Button("Not now") {}.buttonStyle(.kw(.plain, size: .text))
        HStack {
            Button("Back up now") {}.buttonStyle(.kw(.primary, size: .small))
            Button("Confirm") {}.buttonStyle(.kw(.primary, size: .mini))
        }
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
