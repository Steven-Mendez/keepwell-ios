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
        // Placed as on the designer's icon (KEEPWELL LOGO-02): 52% of the tile wide, a touch left
        // of and above center.
        KWLogoMark(size: 40)
            .foregroundStyle(.white)
            .offset(x: -0.85, y: -2.5)
            .frame(width: 72, height: 72)
            .background(
                // The designer's icon gradient (LOGO-02), as in App/Resources/AppIcon.icon/Assets/background.png.
                LinearGradient(
                    colors: [Color(hex: 0x4A74FF), Color(hex: 0x233F91)],
                    startPoint: UnitPoint(x: 0.5, y: -0.076),
                    endPoint: UnitPoint(x: 0.5, y: 0.933),
                ),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous),
            )
    }
}

/// The horizontal lockup (symbol and "KEEPWELL") as the designer drew it for each surface: the
/// full-color lockup (KEEPWELL LOGO-06) on light ones, the white one (LOGO-05) on dark and brand
/// surfaces, which draw in dark.
public struct KWWordmark: View {
    @Environment(\.colorScheme) private var colorScheme
    private let height: CGFloat

    /// - Parameter height: Height of the lockup; the symbol fills it and the name is centered on it.
    public init(height: CGFloat = 50) {
        self.height = height
    }

    public var body: some View {
        Group {
            if colorScheme == .dark {
                Image("KeepwellLockupTemplate", bundle: .module)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(KWColor.Semantic.logo)
            } else {
                Image("KeepwellLockupColor", bundle: .module)
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(height: height)
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
