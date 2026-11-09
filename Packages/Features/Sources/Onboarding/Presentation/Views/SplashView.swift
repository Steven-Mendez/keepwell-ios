import DesignSystem
import SwiftUI

/// Launch splash: the white lockup on the brand gradient.
public struct SplashView: View {
    public init() {}

    public var body: some View {
        KWWordmark(height: 50)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { KWBrandGradient() }
    }
}

#Preview {
    SplashView().onAppear { KWFonts.register() }
}
