import DesignSystem
import SwiftUI

/// Launch splash: wordmark on the brand gradient.
public struct SplashView: View {
    public init() {}

    public var body: some View {
        KWWordmark(markSize: 50, fontSize: 46)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { KWBrandGradient() }
    }
}

#Preview {
    SplashView().onAppear { KWFonts.register() }
}
