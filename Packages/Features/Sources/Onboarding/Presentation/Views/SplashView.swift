import DesignSystem
import SwiftUI

/// Launch splash: the white lockup on the brand gradient, or the blue one on light.
public struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        KWWordmark(height: 50)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // The brand gradient in dark mode; in light mode the light screen with the blue lockup.
                if colorScheme == .dark {
                    KWBrandGradient()
                } else {
                    KWColor.Surface.bg.ignoresSafeArea()
                }
            }
    }
}

#Preview {
    SplashView().onAppear { KWFonts.register() }
}
