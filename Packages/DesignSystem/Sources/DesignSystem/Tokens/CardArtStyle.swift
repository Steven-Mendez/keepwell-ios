import SwiftUI

/// How card art renders for each palette. The two token stops come from `tokens.json`; the
/// screens draw the large cards with an extra mid stop for azul, grafito and lima, kept here so
/// large cards match the design while minis keep the plain two-stop gradient.
extension KWColor.CardArt {
    /// Palettes a person can pick for a card (the add-card color swatches).
    public static let selectable: [Self] = [.azul, .grafito, .verde, .violeta, .coral, .oro]

    public var displayName: String {
        // The cases keep their stored names; only the label a person reads is localized.
        switch self {
        case .azul: String(localized: "Blue", bundle: #bundle)
        case .grafito: String(localized: "Graphite", bundle: #bundle)
        case .verde: String(localized: "Green", bundle: #bundle)
        case .violeta: String(localized: "Violet", bundle: #bundle)
        case .coral: String(localized: "Coral", bundle: #bundle)
        case .oro: String(localized: "Gold", bundle: #bundle)
        case .lima: String(localized: "Lime", bundle: #bundle)
        case .chip: String(localized: "Chip", bundle: #bundle)
        }
    }

    var midStop: (hex: UInt32, location: CGFloat)? {
        switch self {
        case .azul: (KWColor.Hex.Brand.b600, 0.55)
        case .grafito: (0x1E1E24, 0.60)
        case .lima: (0xC2F04E, 0.55)
        default: nil
        }
    }

    /// Large card gradient (135°).
    public var largeGradient: LinearGradient {
        var stops = [Gradient.Stop(color: Color(hex: hexStops.start), location: 0)]
        if let midStop {
            stops.append(Gradient.Stop(color: Color(hex: midStop.hex), location: midStop.location))
        }
        stops.append(Gradient.Stop(color: Color(hex: hexStops.end), location: 1))
        return LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Light art (lima) uses dark text, as the design does.
    public var foreground: Color {
        self == .lima ? KWColor.Text.onExtra : KWColor.Text.primary
    }

    var isLight: Bool {
        self == .lima || self == .chip
    }

    /// Opacity of the soft circles that catch the light; stronger on light art so they still show.
    var orbOpacity: Double {
        switch self {
        case .lima, .chip: 0.20
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
        default: KWShadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 18)
        }
    }
}
