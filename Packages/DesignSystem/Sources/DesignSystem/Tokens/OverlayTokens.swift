import SwiftUI

/// Translucent fills the screens layer over gradients and surfaces. They are token colors at a
/// fixed opacity, named by role so screens never hand-pick alpha values.
extension KWColor {
    public enum Overlay {
        /// Biometric unlock button on the lock screen.
        public static let white10 = Color.white.opacity(0.10)
        /// Feature bullets on the welcome screen.
        public static let white12 = Color.white.opacity(0.12)
        /// Search pill, back button and pills on blue gradients.
        public static let white14 = Color.white.opacity(0.14)
        /// Quick actions and the accounts pill on the home hero; card tags.
        public static let white18 = Color.white.opacity(0.18)
        /// Card tag on light card art (lima).
        public static let black12 = Color.black.opacity(0.12)
        /// System notification banners.
        public static let notification = Color(hex: 0x282834, opacity: 0.82)
        /// Summary card floating over the success glow.
        public static let surfaceTranslucent = KWColor.Surface.surface.opacity(0.9)
    }

    /// Soft backgrounds behind state-colored icons and pills.
    public enum Tint {
        public static let positive = KWColor.State.positive.opacity(0.14)
        public static let pending = KWColor.State.pending.opacity(0.14)
        public static let negative = KWColor.State.negative.opacity(0.14)
        public static let neutral = KWColor.State.neutral.opacity(0.14)
        public static let extra = KWColor.State.extra.opacity(0.14)
        public static let accent = KWColor.Brand.accent.opacity(0.18)
    }
}
