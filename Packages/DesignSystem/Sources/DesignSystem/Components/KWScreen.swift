import SwiftUI

/// Full-screen container that applies the design's edge padding. The screens are drawn on a
/// 390×844 canvas with content starting 56pt from the top (`layout.safeTop`) and a bottom margin
/// per screen; the container measures from the physical edges and never lets content go under
/// the real safe area on devices whose insets are larger.
public struct KWScreen<Content: View, Background: View>: View {
    private let top: CGFloat
    private let bottom: CGFloat
    private let horizontal: CGFloat
    private let background: Background
    private let content: Content

    public init(
        top: CGFloat = KWLayout.safeTop,
        bottom: CGFloat = 40,
        horizontal: CGFloat = KWLayout.gutter,
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: () -> Content,
    ) {
        self.top = top
        self.bottom = bottom
        self.horizontal = horizontal
        self.background = background()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, max(top, proxy.safeAreaInsets.top))
                .padding(.bottom, max(bottom, proxy.safeAreaInsets.bottom))
                .padding(.horizontal, horizontal)
                .frame(
                    width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                    height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom,
                )
                .ignoresSafeArea(.container)
        }
        .background {
            // Empty space is transparent to hits, so taps there reach the background.
            background
                .ignoresSafeArea()
                .onTapGesture { KWKeyboard.dismiss() }
        }
        .foregroundStyle(KWColor.Text.primary)
        // The design lays screens out for the full height; the keyboard covers the lower part
        // instead of squeezing the layout, and screens offer a way to dismiss it.
        .ignoresSafeArea(.keyboard)
    }
}

extension KWScreen where Background == Color {
    public init(
        top: CGFloat = KWLayout.safeTop,
        bottom: CGFloat = 40,
        horizontal: CGFloat = KWLayout.gutter,
        @ViewBuilder content: () -> Content,
    ) {
        self.init(top: top, bottom: bottom, horizontal: horizontal, background: { KWColor.Surface.bg }, content: content)
    }
}

/// Hides the keyboard from anywhere: primary actions and taps on empty space call it, since
/// number pads have no return key.
@MainActor
public enum KWKeyboard {
    public static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
