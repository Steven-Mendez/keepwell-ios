import SwiftUI

/// Radial glows behind hero screens. Each mirrors a CSS `radial-gradient(… at 50% y, color 0%,
/// #000 stop)` from the design; the ellipse is close enough to a circle on a phone to use one.
public struct KWGlowBackground: View {
    public enum Style: Sendable {
        /// Welcome and lock screens: brand blue from the top.
        case brand
        /// Done screens: green from near the top.
        case success
        /// Card added: navy around the card.
        case navy

        var color: Color {
            switch self {
            case .brand: KWColor.Brand.b700
            case .success: Color(hex: KWColor.CardArt.verde.hexStops.end)
            case .navy: KWColor.Brand.b900
            }
        }

        var center: UnitPoint {
            switch self {
            case .brand: .top
            case .success: UnitPoint(x: 0.5, y: 0.1)
            case .navy: UnitPoint(x: 0.5, y: 0.2)
            }
        }

        /// Fraction of the 844pt screen height where the glow fades to black.
        var fade: CGFloat {
            switch self {
            case .brand: 0.55 * 0.7
            case .success: 0.55 * 0.65
            case .navy: 0.5 * 0.7
            }
        }
    }

    private let style: Style

    public init(_ style: Style) {
        self.style = style
    }

    public var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [style.color, .black],
                center: style.center,
                startRadius: 0,
                endRadius: proxy.size.height * style.fade,
            )
        }
        .ignoresSafeArea()
    }
}

/// The splash and logo gradient (160°, brand 500 → 700).
public struct KWBrandGradient: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [KWColor.Brand.b500, KWColor.Brand.b700],
            startPoint: UnitPoint(x: 0.33, y: 0),
            endPoint: UnitPoint(x: 0.67, y: 1),
        )
        .ignoresSafeArea()
    }
}
