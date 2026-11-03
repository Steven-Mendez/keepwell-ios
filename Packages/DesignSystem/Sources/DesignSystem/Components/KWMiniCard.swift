import SwiftUI

/// Small card thumbnails used in rows. `small` (46×29) and `medium` (58×37) follow the design;
/// `tiny` (40×26) is the onboarding list thumbnail.
public struct KWMiniCard: View {
    public enum Size: Sendable {
        case tiny
        case small
        case medium

        var dimensions: CGSize {
            switch self {
            case .tiny: CGSize(width: 40, height: 26)
            case .small: CGSize(width: 46, height: 29)
            case .medium: CGSize(width: 58, height: 37)
            }
        }

        var cornerRadius: CGFloat {
            self == .medium ? 6 : KWRadius.mini
        }
    }

    public enum Style: Sendable {
        /// Card palette, optionally with a small chip.
        case palette(KWColor.CardArt, chip: Bool = false)
        /// Flat color (cash, the onboarding credit thumbnail).
        case solid(Color)
        /// Bank transfer method: neutral tile with the transfer arrows.
        case transfer
        /// Dashed outline inviting to link another card.
        case add
        /// Neutral tile with no artwork.
        case neutral
    }

    private let style: Style
    private let size: Size

    public init(_ style: Style, size: Size = .small) {
        self.style = style
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius)
        ZStack(alignment: .leading) {
            switch style {
            case let .palette(palette, chip):
                shape.fill(palette.gradient)
                TopHighlight(shape: shape, opacity: palette.isLight ? 0.5 : 0.3)
                if chip {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: KWColor.CardArt.chip.hexStops.start))
                        .frame(width: 9, height: 7)
                        .padding(.leading, 6)
                }
            case let .solid(color):
                shape.fill(color)
            case .transfer:
                shape.fill(KWColor.Surface.surface2)
                KWIconView(.transfer, size: 14, lineWidth: 2.2)
                    .foregroundStyle(KWColor.Text.secondary)
                    .frame(maxWidth: .infinity)
            case .add:
                shape.strokeBorder(KWColor.Surface.controlOff, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            case .neutral:
                shape.fill(KWColor.Surface.surface2)
            }
        }
        .frame(width: size.dimensions.width, height: size.dimensions.height)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: KWSpacing.sm) {
        KWMiniCard(.palette(.coral, chip: true))
        KWMiniCard(.palette(.azul), size: .medium)
        KWMiniCard(.transfer)
        KWMiniCard(.add)
        KWMiniCard(.solid(KWColor.Brand.b500), size: .tiny)
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
}
