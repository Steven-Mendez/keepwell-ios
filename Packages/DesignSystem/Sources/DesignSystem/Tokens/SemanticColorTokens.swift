import SwiftUI

/// Colors by role, the vocabulary iOS and the web app share: the names match the shadcn/ui CSS
/// variables the web components read (`card` is `--card`, `mutedForeground` is
/// `--muted-foreground`), plus Keepwell's own roles. Screens can say what a color is for instead of
/// which shade it is, and a designer's "card" or "positive" means the same thing on both platforms.
extension KWColor {
    public enum Semantic {
        public static let background = Color(hex: Hex.Semantic.background)
        public static let foreground = Color(hex: Hex.Semantic.foreground)
        public static let card = Color(hex: Hex.Semantic.card)
        public static let cardForeground = Color(hex: Hex.Semantic.cardForeground)
        public static let popover = Color(hex: Hex.Semantic.popover)
        public static let popoverForeground = Color(hex: Hex.Semantic.popoverForeground)
        public static let primary = Color(hex: Hex.Semantic.primary)
        public static let primaryForeground = Color(hex: Hex.Semantic.primaryForeground)
        public static let secondary = Color(hex: Hex.Semantic.secondary)
        public static let secondaryForeground = Color(hex: Hex.Semantic.secondaryForeground)
        public static let muted = Color(hex: Hex.Semantic.muted)
        public static let mutedForeground = Color(hex: Hex.Semantic.mutedForeground)
        public static let accent = Color(hex: Hex.Semantic.accent)
        public static let accentForeground = Color(hex: Hex.Semantic.accentForeground)
        public static let destructive = Color(hex: Hex.Semantic.destructive)
        public static let border = Color(hex: Hex.Semantic.border)
        public static let input = Color(hex: Hex.Semantic.input)
        public static let ring = Color(hex: Hex.Semantic.ring)
        public static let positive = Color(hex: Hex.Semantic.positive)
        public static let positiveForeground = Color(hex: Hex.Semantic.positiveForeground)
        public static let pending = Color(hex: Hex.Semantic.pending)
        public static let negative = Color(hex: Hex.Semantic.negative)
        public static let extra = Color(hex: Hex.Semantic.extra)
        public static let extraForeground = Color(hex: Hex.Semantic.extraForeground)
        /// Movements that don't change what the person has, like a transfer between their own accounts.
        public static let neutral = Color(hex: Hex.Semantic.neutral)
        public static let textSecondary = Color(hex: Hex.Semantic.textSecondary)
        public static let textFaint = Color(hex: Hex.Semantic.textFaint)
        public static let link = Color(hex: Hex.Semantic.link)
        public static let linkHover = Color(hex: Hex.Semantic.linkHover)
        /// Text on the brand gradient.
        public static let brandForeground = Color(hex: Hex.Semantic.brandForeground)
        public static let nav = Color(hex: Hex.Semantic.nav)
        public static let divider = Color(hex: Hex.Semantic.divider)
        public static let controlOff = Color(hex: Hex.Semantic.controlOff)
    }
}

extension KWColor.Hex {
    /// Each role points at a palette token, as the components already use it: the primary button
    /// is white on black, secondary rows and inputs sit on `surface2`, focus is the brand accent.
    /// keepwell-web's `pnpm tokens:sync` reads this file, so keep one `static let` per line, set
    /// to a palette token or a `0xRRGGBB` literal.
    enum Semantic {
        static let background = Surface.bg
        static let foreground = Text.primary
        static let card = Surface.surface
        static let cardForeground = Text.primary
        static let popover = Surface.surface
        static let popoverForeground = Text.primary
        static let primary: UInt32 = 0xFFFFFF
        static let primaryForeground: UInt32 = 0x000000
        static let secondary = Surface.surface2
        static let secondaryForeground = Text.primary
        static let muted = Surface.surface2
        static let mutedForeground = Text.muted
        static let accent = Surface.surface2
        static let accentForeground = Text.primary
        static let destructive = State.negative
        static let border = Surface.border
        static let input = Surface.border
        static let ring = Brand.accent
        static let positive = State.positive
        static let positiveForeground = Text.onPositive
        static let pending = State.pending
        static let negative = State.negative
        static let extra = State.extra
        static let extraForeground = Text.onExtra
        static let neutral = Text.secondary
        static let textSecondary = Text.secondary
        static let textFaint = Text.faint
        static let link = Brand.link
        static let linkHover = Brand.linkHover
        static let brandForeground = Text.onBrand
        static let nav = Surface.nav
        static let divider = Surface.divider
        static let controlOff = Surface.controlOff
    }
}
