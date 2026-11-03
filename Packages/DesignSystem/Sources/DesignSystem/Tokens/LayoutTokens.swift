import CoreGraphics
import SwiftUI

public enum KWSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 56

    /// The full scale, in order.
    public static let scale: [CGFloat] = [xxs, xs, sm, md, lg, xl, xxl, xxxl]
}

public enum KWLayout {
    public static let gutter: CGFloat = 16
    public static let safeTop: CGFloat = 56
    public static let minTouch: CGFloat = 44
    public static let tabBar: CGFloat = 84
}

public enum KWRadius {
    public static let mini: CGFloat = 5
    public static let input: CGFloat = 12
    public static let card: CGFloat = 18
    public static let surface: CGFloat = 20
    public static let full: CGFloat = 9999
}

/// The original CSS "inset" is approximated with a top highlight border in components.
public struct KWShadow: Sendable, Equatable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    /// `0 18px 40px rgba(36,72,224,0.40)`
    public static let glow = Self(color: Color(hex: 0x2448E0, opacity: 0.40), radius: 20, x: 0, y: 18)
    /// `0 10px 30px rgba(0,0,0,0.60)`
    public static let depth = Self(color: Color(hex: 0x000000, opacity: 0.60), radius: 15, x: 0, y: 10)
}

extension View {
    public func kwShadow(_ shadow: KWShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

public enum KWComponentMetrics {
    public static let buttonHeight: CGFloat = 54
    public static let chipHeight: CGFloat = 36
    public static let switchSize = CGSize(width: 52, height: 32)
    public static let actionCircle: CGFloat = 48
    /// Width a row of two quick actions takes, so the pair sits together under a card.
    public static let actionPairWidth: CGFloat = 220
    public static let cardArtRatio: CGFloat = 1.586
    public static let iconStroke: CGFloat = 2
    public static let iconSizes: [CGFloat] = [20, 24]
}
