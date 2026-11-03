import SwiftUI

extension Font {
    /// Inter at an exact design size and CSS weight, for the few spots the screens size text
    /// outside the type scale (splash wordmark, keypad digits, card numbers).
    public static func kw(_ size: CGFloat, weight cssWeight: Int, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(KWFonts.Weight(cssWeight: cssWeight).postScriptName, size: size, relativeTo: textStyle)
    }
}
