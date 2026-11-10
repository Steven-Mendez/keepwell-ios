import SwiftUI

/// The keepwell symbol (wallet with a padlock shackle) in one color, tinted by `foregroundStyle`
/// so it can sit on any background, including widgets in tinted or accented rendering.
public struct KWLogoMark: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Image("KeepwellSymbolTemplate", bundle: .module)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The app icon in miniature (72pt, radius 17): the white symbol on the icon's blue tile, so the
/// lock screen and app switcher match what the person tapped on the Home Screen.
public struct KWAppIconTile: View {
    public init() {}

    public var body: some View {
        // Placed as on the icon: 52% of the tile wide, slightly above center.
        KWLogoMark(size: 40)
            .foregroundStyle(.white)
            .offset(y: -2.5)
            .frame(width: 72, height: 72)
            .background(
                // Same stops as App/Resources/AppIcon.icon/Assets/background.png.
                LinearGradient(colors: [KWColor.Brand.b500, KWColor.Brand.b700], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous),
            )
            .overlay { TopHighlight(shape: RoundedRectangle(cornerRadius: 17, style: .continuous), opacity: 0.3) }
    }
}

/// The horizontal lockup (symbol and "KEEPWELL") in the logo color: white on dark and brand
/// surfaces, the brand blue on light ones.
public struct KWWordmark: View {
    private let height: CGFloat

    /// - Parameter height: Height of the lockup; the symbol fills it and the name is centered on it.
    public init(height: CGFloat = 50) {
        self.height = height
    }

    public var body: some View {
        Image("KeepwellLockupTemplate", bundle: .module)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(KWColor.Semantic.logo)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "Keepwell"))
    }
}

#Preview {
    VStack(spacing: KWSpacing.xl) {
        KWAppIconTile()
        KWWordmark()
        KWLogoMark(size: 28).foregroundStyle(KWColor.Semantic.logo)
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Brand.b700)
}
