import SwiftUI

/// Every color the app draws with. Surfaces, text, links and states are light/dark pairs that follow
/// the system appearance (`Hex.Light` and `Hex`); the brand scale and card art are fixed, so the
/// brand moments (home hero, lock, splash, icon tile, receipt) look the same in both modes.
public enum KWColor {
    public enum Surface {
        public static let bg = Color(light: Hex.Light.Surface.bg, dark: Hex.Surface.bg)
        public static let nav = Color(light: Hex.Light.Surface.nav, dark: Hex.Surface.nav)
        public static let surface = Color(light: Hex.Light.Surface.surface, dark: Hex.Surface.surface)
        public static let surface2 = Color(light: Hex.Light.Surface.surface2, dark: Hex.Surface.surface2)
        public static let divider = Color(light: Hex.Light.Surface.divider, dark: Hex.Surface.divider)
        public static let border = Color(light: Hex.Light.Surface.border, dark: Hex.Surface.border)
        public static let controlOff = Color(light: Hex.Light.Surface.controlOff, dark: Hex.Surface.controlOff)
        public static let light = Color(light: Hex.Light.Surface.light, dark: Hex.Surface.light)
    }

    public enum Text {
        public static let primary = Color(light: Hex.Light.Text.primary, dark: Hex.Text.primary)
        public static let secondary = Color(light: Hex.Light.Text.secondary, dark: Hex.Text.secondary)
        public static let muted = Color(light: Hex.Light.Text.muted, dark: Hex.Text.muted)
        public static let faint = Color(light: Hex.Light.Text.faint, dark: Hex.Text.faint)
        public static let onBrand = Color(light: Hex.Light.Text.onBrand, dark: Hex.Text.onBrand)
        public static let onPositive = Color(light: Hex.Light.Text.onPositive, dark: Hex.Text.onPositive)
        public static let onExtra = Color(light: Hex.Light.Text.onExtra, dark: Hex.Text.onExtra)
    }

    public enum Brand {
        // The scale is fixed: it paints the brand gradients, which stay dark-styled in light mode.
        public static let b500 = Color(hex: Hex.Brand.b500)
        public static let b600 = Color(hex: Hex.Brand.b600)
        public static let b700 = Color(hex: Hex.Brand.b700)
        public static let b900 = Color(hex: Hex.Brand.b900)
        public static let accent = Color(light: Hex.Light.Brand.accent, dark: Hex.Brand.accent)
        public static let link = Color(light: Hex.Light.Brand.link, dark: Hex.Brand.link)
        public static let linkHover = Color(light: Hex.Light.Brand.linkHover, dark: Hex.Brand.linkHover)
        public static let gradient = LinearGradient(
            colors: [b500, b700],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
    }

    public enum State {
        public static let positive = Color(light: Hex.Light.State.positive, dark: Hex.State.positive)
        public static let pending = Color(light: Hex.Light.State.pending, dark: Hex.State.pending)
        public static let negative = Color(light: Hex.Light.State.negative, dark: Hex.State.negative)
        /// Movements that don't change what the person has, like a transfer between their own
        /// accounts, so they carry no gain or loss color.
        public static let neutral = KWColor.Text.secondary
        public static let extra = Color(light: Hex.Light.State.extra, dark: Hex.State.extra)
    }

    /// Card art (two-stop gradients). `violeta`, `coral` and `lima` are no longer offered but still
    /// draw cards saved with them.
    public enum CardArt: String, CaseIterable, Sendable {
        case azul
        case grafito
        case platino
        case verde
        case violeta
        case coral
        case rojo
        case oro
        case lima
        case chip

        public var hexStops: (start: UInt32, end: UInt32) {
            switch self {
            case .azul: (0x4A74FF, 0x1A33A8)
            case .grafito: (0x3A3A44, 0x121216)
            case .platino: (0xE4E6EA, 0x8C919B)
            case .verde: (0x1FC28E, 0x0B6B4F)
            case .violeta: (0xA47BFF, 0x5A2FD0)
            case .coral: (0xFF7A50, 0xC93A12)
            case .rojo: (0xD8323F, 0x6E0B17)
            case .oro: (0xEDD596, 0x9A7429)
            case .lima: (0xE4FC98, 0x9CD228)
            case .chip: (0xF3E6BC, 0xB99A5C)
            }
        }

        public var gradient: LinearGradient {
            LinearGradient(
                colors: [Color(hex: hexStops.start), Color(hex: hexStops.end)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        }
    }

    /// Per-category colors, keyed by the stable category id so a color doesn't depend on the
    /// language of the name. Categories without their own color use `faint`.
    public static let category: [String: UInt32] = [
        "tools": 0x5B7CFF,
        "restaurants": 0xFFB547,
        "fees": 0x3FD69A,
        "transport": 0xC77DFF,
        "utilities": 0x4FD1E8,
        "leisure": 0xFF7A90,
        "shopping": 0xFF8A50,
        "subscriptions": 0xA3E635,
        "education": 0xF2D16B,
        "loan-payments": 0x3FD69A,
        "other-expense": 0x8A8A96,
    ]

    public static func category(id: String) -> Color {
        Color(hex: category[id] ?? Hex.Text.faint)
    }

    /// The colors a person can give a category they create, by key so the stored value stays a
    /// name rather than a UI color. Same hues as `category`, so their rows sit with the defaults.
    public static let categoryPalette: [(key: String, hex: UInt32)] = [
        ("blue", 0x5B7CFF),
        ("purple", 0xC77DFF),
        ("pink", 0xFF7A90),
        ("orange", 0xFF8A50),
        ("amber", 0xFFB547),
        ("yellow", 0xF2D16B),
        ("lime", 0xA3E635),
        ("green", 0x3FD69A),
        ("cyan", 0x4FD1E8),
        ("gray", 0x8A8A96),
    ]

    public static func categoryPalette(key: String) -> Color? {
        categoryPalette.first { $0.key == key }.map { Color(hex: $0.hex) }
    }

    /// The dark palette, the app's original look. `Light` mirrors it name for name.
    enum Hex {
        enum Surface {
            static let bg: UInt32 = 0x000000
            static let nav: UInt32 = 0x0B0B0D
            static let surface: UInt32 = 0x16161A
            static let surface2: UInt32 = 0x26262D
            static let divider: UInt32 = 0x24242A
            static let border: UInt32 = 0x2A2A31
            static let controlOff: UInt32 = 0x3A3A44
            static let light: UInt32 = 0xEDEDF2
        }

        enum Text {
            static let primary: UInt32 = 0xFFFFFF
            static let secondary: UInt32 = 0xC9C9D2
            static let muted: UInt32 = 0x9A9AA6
            static let faint: UInt32 = 0x8A8A96
            static let onBrand: UInt32 = 0xC7CDEB
            static let onPositive: UInt32 = 0x00261A
            static let onExtra: UInt32 = 0x152000
        }

        enum Brand {
            static let b500: UInt32 = 0x4A74FF
            static let b600: UInt32 = 0x2448E0
            static let b700: UInt32 = 0x1A33A8
            static let b900: UInt32 = 0x0B1550
            static let accent: UInt32 = 0x5B7CFF
            static let link: UInt32 = 0x8FA8FF
            static let linkHover: UInt32 = 0xB8C7FF
        }

        enum State {
            static let positive: UInt32 = 0x3FD69A
            static let pending: UInt32 = 0xFFB547
            static let negative: UInt32 = 0xFF8A7F
            static let extra: UInt32 = 0xC8F560
        }
    }
}

extension KWColor.Hex {
    /// The light palette, derived from the dark one: the same blue identity on white and light gray
    /// grouped surfaces, with navy text. Accents, links and states are deepened where the dark
    /// value would fall under WCAG AA (4.5:1) on white. keepwell-web's `pnpm tokens:sync` reads
    /// this enum too, so it keeps the dark palette's names and one `static let` per line.
    enum Light {
        enum Surface {
            static let bg: UInt32 = 0xF2F3F7
            static let nav: UInt32 = 0xFBFBFD
            static let surface: UInt32 = 0xFFFFFF
            static let surface2: UInt32 = 0xEAECF1
            static let divider: UInt32 = 0xE3E5EB
            static let border: UInt32 = 0xD9DCE4
            static let controlOff: UInt32 = 0xC9CCD6
            static let light: UInt32 = 0xEDEDF2
        }

        enum Text {
            static let primary: UInt32 = 0x0D1226
            static let secondary: UInt32 = 0x3B4054
            static let muted: UInt32 = 0x5B6074
            static let faint: UInt32 = 0x60657A
            static let onBrand: UInt32 = 0x4A5070
            static let onPositive: UInt32 = 0xFFFFFF
            static let onExtra: UInt32 = 0xFFFFFF
        }

        enum Brand {
            static let b500: UInt32 = 0x4A74FF
            static let b600: UInt32 = 0x2448E0
            static let b700: UInt32 = 0x1A33A8
            static let b900: UInt32 = 0x0B1550
            static let accent: UInt32 = 0x2448E0
            static let link: UInt32 = 0x2448E0
            static let linkHover: UInt32 = 0x1A33A8
        }

        enum State {
            static let positive: UInt32 = 0x087550
            static let pending: UInt32 = 0x965400
            static let negative: UInt32 = 0xC22B28
            static let extra: UInt32 = 0x44700B
        }
    }
}

extension Color {
    /// A color that follows the appearance it is drawn in: the system's, or the `colorScheme`
    /// a view sets for its subtree. Anything that isn't explicitly light draws the dark value,
    /// the app's original look.
    init(light: UInt32, dark: UInt32) {
        let light = UIColor(hex: light)
        let dark = UIColor(hex: dark)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .light ? light : dark })
    }
}
