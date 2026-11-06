import SwiftUI

/// How card art renders for each palette. The two token stops come from `tokens.json`; the
/// screens draw the large cards with extra stops for some palettes, kept here so large cards match
/// the design while minis keep the plain two-stop gradient.
extension KWColor.CardArt {
    /// Palettes a person can pick for a card, in the tiers and colors banks actually issue: black,
    /// platinum and gold first, then the classic blue, green and red.
    public static let selectable: [Self] = [.grafito, .platino, .oro, .azul, .verde, .rojo]

    public var displayName: String {
        // The cases keep their stored names; only the label a person reads is localized.
        switch self {
        case .azul: String(localized: "Blue", bundle: #bundle)
        // Read as "black": the name people give the premium dark cards.
        case .grafito: String(localized: "Black", bundle: #bundle)
        case .platino: String(localized: "Platinum", bundle: #bundle)
        case .verde: String(localized: "Green", bundle: #bundle)
        case .violeta: String(localized: "Violet", bundle: #bundle)
        case .coral: String(localized: "Coral", bundle: #bundle)
        case .rojo: String(localized: "Red", bundle: #bundle)
        case .oro: String(localized: "Gold", bundle: #bundle)
        case .lima: String(localized: "Lime", bundle: #bundle)
        case .chip: String(localized: "Chip", bundle: #bundle)
        }
    }

    /// Stops between the two token ones. Metallic palettes get a bright band across the middle,
    /// the light a brushed-metal plastic catches, so they read as metal rather than flat beige or gray.
    var innerStops: [(hex: UInt32, location: CGFloat)] {
        switch self {
        case .azul: [(KWColor.Hex.Brand.b600, 0.55)]
        case .grafito: [(0x1E1E24, 0.60)]
        case .lima: [(0xC2F04E, 0.55)]
        case .platino: [(0xF7F8FA, 0.38), (0xBFC3CA, 0.64)]
        case .oro: [(0xF8EBC1, 0.36), (0xC9A253, 0.64)]
        default: []
        }
    }

    /// Large card gradient (135°).
    public var largeGradient: LinearGradient {
        var stops = [Gradient.Stop(color: Color(hex: hexStops.start), location: 0)]
        stops += innerStops.map { Gradient.Stop(color: Color(hex: $0.hex), location: $0.location) }
        stops.append(Gradient.Stop(color: Color(hex: hexStops.end), location: 1))
        return LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Light art uses dark text, as the design does for lima; metallic art prints in a dark tone
    /// of its own metal, like the embossing on a real platinum or gold card.
    public var foreground: Color {
        switch self {
        case .lima: KWColor.Text.onExtra
        case .platino: Color(hex: 0x24272D)
        case .oro: Color(hex: 0x3A2908)
        default: KWColor.Text.primary
        }
    }

    var isLight: Bool {
        switch self {
        case .lima, .chip, .platino, .oro: true
        default: false
        }
    }

    /// Opacity of the soft circles that catch the light; stronger on light art so they still show.
    var orbOpacity: Double {
        switch self {
        case .lima, .chip: 0.20
        case .platino, .oro: 0.16
        case .grafito: 0.05
        default: 0.09
        }
    }

    /// Colored glow under the large card; graphite cards use the neutral depth shadow instead.
    var glow: KWShadow {
        switch self {
        case .grafito: .depth
        case .lima: KWShadow(color: Color(hex: 0xC2F04E, opacity: 0.28), radius: 20, x: 0, y: 18)
        case .azul: .glow
        case .platino: KWShadow(color: Color(hex: 0xC9CDD4, opacity: 0.22), radius: 20, x: 0, y: 18)
        case .oro: KWShadow(color: Color(hex: 0xD9B465, opacity: 0.26), radius: 20, x: 0, y: 18)
        default: KWShadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 18)
        }
    }
}
