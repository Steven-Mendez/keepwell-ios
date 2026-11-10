import SwiftUI

/// Colors by role, the vocabulary iOS and the web app share: the names match the shadcn/ui CSS
/// variables the web components read (`card` is `--card`, `mutedForeground` is
/// `--muted-foreground`), plus Keepwell's own roles. Screens can say what a color is for instead of
/// which shade it is, and a designer's "card" or "positive" means the same thing on both platforms.
extension KWColor {
    public enum Semantic {
        public static let background = Color(light: Hex.Light.Semantic.background, dark: Hex.Semantic.background)
        public static let foreground = Color(light: Hex.Light.Semantic.foreground, dark: Hex.Semantic.foreground)
        public static let card = Color(light: Hex.Light.Semantic.card, dark: Hex.Semantic.card)
        public static let cardForeground = Color(light: Hex.Light.Semantic.cardForeground, dark: Hex.Semantic.cardForeground)
        public static let popover = Color(light: Hex.Light.Semantic.popover, dark: Hex.Semantic.popover)
        public static let popoverForeground = Color(light: Hex.Light.Semantic.popoverForeground, dark: Hex.Semantic.popoverForeground)
        public static let primary = Color(light: Hex.Light.Semantic.primary, dark: Hex.Semantic.primary)
        public static let primaryForeground = Color(light: Hex.Light.Semantic.primaryForeground, dark: Hex.Semantic.primaryForeground)
        public static let secondary = Color(light: Hex.Light.Semantic.secondary, dark: Hex.Semantic.secondary)
        public static let secondaryForeground = Color(light: Hex.Light.Semantic.secondaryForeground, dark: Hex.Semantic.secondaryForeground)
        public static let muted = Color(light: Hex.Light.Semantic.muted, dark: Hex.Semantic.muted)
        public static let mutedForeground = Color(light: Hex.Light.Semantic.mutedForeground, dark: Hex.Semantic.mutedForeground)
        public static let accent = Color(light: Hex.Light.Semantic.accent, dark: Hex.Semantic.accent)
        public static let accentForeground = Color(light: Hex.Light.Semantic.accentForeground, dark: Hex.Semantic.accentForeground)
        public static let destructive = Color(light: Hex.Light.Semantic.destructive, dark: Hex.Semantic.destructive)
        public static let border = Color(light: Hex.Light.Semantic.border, dark: Hex.Semantic.border)
        public static let input = Color(light: Hex.Light.Semantic.input, dark: Hex.Semantic.input)
        public static let ring = Color(light: Hex.Light.Semantic.ring, dark: Hex.Semantic.ring)
        public static let positive = Color(light: Hex.Light.Semantic.positive, dark: Hex.Semantic.positive)
        public static let positiveForeground = Color(light: Hex.Light.Semantic.positiveForeground, dark: Hex.Semantic.positiveForeground)
        public static let pending = Color(light: Hex.Light.Semantic.pending, dark: Hex.Semantic.pending)
        public static let negative = Color(light: Hex.Light.Semantic.negative, dark: Hex.Semantic.negative)
        public static let extra = Color(light: Hex.Light.Semantic.extra, dark: Hex.Semantic.extra)
        public static let extraForeground = Color(light: Hex.Light.Semantic.extraForeground, dark: Hex.Semantic.extraForeground)
        /// Movements that don't change what the person has, like a transfer between their own accounts.
        public static let neutral = Color(light: Hex.Light.Semantic.neutral, dark: Hex.Semantic.neutral)
        public static let textSecondary = Color(light: Hex.Light.Semantic.textSecondary, dark: Hex.Semantic.textSecondary)
        public static let textFaint = Color(light: Hex.Light.Semantic.textFaint, dark: Hex.Semantic.textFaint)
        public static let link = Color(light: Hex.Light.Semantic.link, dark: Hex.Semantic.link)
        public static let linkHover = Color(light: Hex.Light.Semantic.linkHover, dark: Hex.Semantic.linkHover)
        /// Text on the brand gradient.
        public static let brandForeground = Color(light: Hex.Light.Semantic.brandForeground, dark: Hex.Semantic.brandForeground)
        public static let nav = Color(light: Hex.Light.Semantic.nav, dark: Hex.Semantic.nav)
        public static let divider = Color(light: Hex.Light.Semantic.divider, dark: Hex.Semantic.divider)
        public static let controlOff = Color(light: Hex.Light.Semantic.controlOff, dark: Hex.Semantic.controlOff)
        /// The logo's one color: white on dark surfaces, the brand blue on light ones. Brand
        /// surfaces draw in dark, so their logo stays white in both modes.
        public static let logo = Color(light: Hex.Light.Semantic.logo, dark: Hex.Semantic.logo)
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
        static let logo: UInt32 = 0xFFFFFF
    }
}

extension KWColor.Hex.Light {
    /// The same roles in light mode, pointing at the light palette (`Surface.bg` here is
    /// `Light.Surface.bg`). The primary action turns from white-on-black into white on the brand
    /// blue, deepened to `b600` so its label passes AA. Same one-`static let`-per-line rule.
    enum Semantic {
        static let background = Surface.bg
        static let foreground = Text.primary
        static let card = Surface.surface
        static let cardForeground = Text.primary
        static let popover = Surface.surface
        static let popoverForeground = Text.primary
        static let primary = Brand.b600
        static let primaryForeground: UInt32 = 0xFFFFFF
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
        static let logo = Brand.b600
    }
}
