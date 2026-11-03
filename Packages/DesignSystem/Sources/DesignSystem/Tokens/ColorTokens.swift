import SwiftUI

public enum KWColor {
    public enum Surface {
        public static let bg = Color(hex: Hex.Surface.bg)
        public static let nav = Color(hex: Hex.Surface.nav)
        public static let surface = Color(hex: Hex.Surface.surface)
        public static let surface2 = Color(hex: Hex.Surface.surface2)
        public static let divider = Color(hex: Hex.Surface.divider)
        public static let border = Color(hex: Hex.Surface.border)
        public static let controlOff = Color(hex: Hex.Surface.controlOff)
        public static let light = Color(hex: Hex.Surface.light)
    }

    public enum Text {
        public static let primary = Color(hex: Hex.Text.primary)
        public static let secondary = Color(hex: Hex.Text.secondary)
        public static let muted = Color(hex: Hex.Text.muted)
        public static let faint = Color(hex: Hex.Text.faint)
        public static let onBrand = Color(hex: Hex.Text.onBrand)
        public static let onPositive = Color(hex: Hex.Text.onPositive)
        public static let onExtra = Color(hex: Hex.Text.onExtra)
    }

    public enum Brand {
        public static let b500 = Color(hex: Hex.Brand.b500)
        public static let b600 = Color(hex: Hex.Brand.b600)
        public static let b700 = Color(hex: Hex.Brand.b700)
        public static let b900 = Color(hex: Hex.Brand.b900)
        public static let accent = Color(hex: Hex.Brand.accent)
        public static let link = Color(hex: Hex.Brand.link)
        public static let linkHover = Color(hex: Hex.Brand.linkHover)
        public static let gradient = LinearGradient(
            colors: [b500, b700],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
    }

    public enum State {
        public static let positive = Color(hex: Hex.State.positive)
        public static let pending = Color(hex: Hex.State.pending)
        public static let negative = Color(hex: Hex.State.negative)
        /// Movements that don't change what the person has, like a transfer between their own
        /// accounts, so they carry no gain or loss color.
        public static let neutral = KWColor.Text.secondary
        public static let extra = Color(hex: Hex.State.extra)
    }

    /// Card art (two-stop gradients).
    public enum CardArt: String, CaseIterable, Sendable {
        case azul
        case grafito
        case verde
        case violeta
        case coral
        case oro
        case lima
        case chip

        public var hexStops: (start: UInt32, end: UInt32) {
            switch self {
            case .azul: (0x4A74FF, 0x1A33A8)
            case .grafito: (0x3A3A44, 0x121216)
            case .verde: (0x1FC28E, 0x0B6B4F)
            case .violeta: (0xA47BFF, 0x5A2FD0)
            case .coral: (0xFF7A50, 0xC93A12)
            case .oro: (0xE2C27A, 0x8E6B26)
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
