import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

@Suite("Color tokens")
@MainActor
struct ColorTokenTests {
    private typealias Hex = KWColor.Hex
    private typealias Light = KWColor.Hex.Light

    /// Every light/dark token with the two values it must resolve to.
    private struct Pair {
        let name: String
        let color: Color
        let light: UInt32
        let dark: UInt32

        init(_ name: String, _ color: Color, _ light: UInt32, _ dark: UInt32) {
            self.name = name
            self.color = color
            self.light = light
            self.dark = dark
        }
    }

    private static let pairs: [Pair] = [
        Pair("Surface.bg", KWColor.Surface.bg, Light.Surface.bg, Hex.Surface.bg),
        Pair("Surface.nav", KWColor.Surface.nav, Light.Surface.nav, Hex.Surface.nav),
        Pair("Surface.surface", KWColor.Surface.surface, Light.Surface.surface, Hex.Surface.surface),
        Pair("Surface.surface2", KWColor.Surface.surface2, Light.Surface.surface2, Hex.Surface.surface2),
        Pair("Surface.divider", KWColor.Surface.divider, Light.Surface.divider, Hex.Surface.divider),
        Pair("Surface.border", KWColor.Surface.border, Light.Surface.border, Hex.Surface.border),
        Pair("Surface.controlOff", KWColor.Surface.controlOff, Light.Surface.controlOff, Hex.Surface.controlOff),
        Pair("Text.primary", KWColor.Text.primary, Light.Text.primary, Hex.Text.primary),
        Pair("Text.secondary", KWColor.Text.secondary, Light.Text.secondary, Hex.Text.secondary),
        Pair("Text.muted", KWColor.Text.muted, Light.Text.muted, Hex.Text.muted),
        Pair("Text.faint", KWColor.Text.faint, Light.Text.faint, Hex.Text.faint),
        Pair("Text.onBrand", KWColor.Text.onBrand, Light.Text.onBrand, Hex.Text.onBrand),
        Pair("Text.onPositive", KWColor.Text.onPositive, Light.Text.onPositive, Hex.Text.onPositive),
        Pair("Brand.accent", KWColor.Brand.accent, Light.Brand.accent, Hex.Brand.accent),
        Pair("Brand.link", KWColor.Brand.link, Light.Brand.link, Hex.Brand.link),
        Pair("State.positive", KWColor.State.positive, Light.State.positive, Hex.State.positive),
        Pair("State.pending", KWColor.State.pending, Light.State.pending, Hex.State.pending),
        Pair("State.negative", KWColor.State.negative, Light.State.negative, Hex.State.negative),
        Pair("State.extra", KWColor.State.extra, Light.State.extra, Hex.State.extra),
        Pair("Semantic.primary", KWColor.Semantic.primary, Light.Semantic.primary, Hex.Semantic.primary),
        Pair(
            "Semantic.primaryForeground",
            KWColor.Semantic.primaryForeground,
            Light.Semantic.primaryForeground,
            Hex.Semantic.primaryForeground,
        ),
        Pair("Semantic.logo", KWColor.Semantic.logo, Light.Semantic.logo, Hex.Semantic.logo),
    ]

    private static func resolved(_ color: Color, _ style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let byte = { (value: CGFloat) in UInt32((value * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    /// Dark is the app's original look: every token must still resolve to its old value.
    @Test
    func darkAndUnspecifiedResolveToTheOriginalValue() {
        for pair in Self.pairs {
            #expect(Self.resolved(pair.color, .dark) == pair.dark, "\(pair.name)")
            #expect(Self.resolved(pair.color, .unspecified) == pair.dark, "\(pair.name)")
        }
    }

    @Test
    func lightResolvesToTheLightPalette() {
        for pair in Self.pairs {
            #expect(Self.resolved(pair.color, .light) == pair.light, "\(pair.name)")
        }
    }

    @Test
    func brandScaleIsTheSameInBothAppearances() {
        for color in [KWColor.Brand.b500, KWColor.Brand.b600, KWColor.Brand.b700, KWColor.Brand.b900] {
            #expect(Self.resolved(color, .light) == Self.resolved(color, .dark))
        }
    }

    /// WCAG relative luminance of a `0xRRGGBB` color.
    private static func luminance(_ hex: UInt32) -> Double {
        let channel = { (shift: UInt32) -> Double in
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Text colors in light mode pass AA (4.5:1) on every surface text sits on.
    @Test
    func lightTextPassesAAOnLightSurfaces() {
        let text: [(String, UInt32)] = [
            ("primary", Light.Text.primary), ("secondary", Light.Text.secondary), ("muted", Light.Text.muted),
            ("faint", Light.Text.faint), ("onBrand", Light.Text.onBrand), ("link", Light.Brand.link),
            ("accent", Light.Brand.accent), ("positive", Light.State.positive), ("pending", Light.State.pending),
            ("negative", Light.State.negative), ("extra", Light.State.extra),
        ]
        for (name, color) in text {
            for surface in [Light.Surface.bg, Light.Surface.surface, Light.Surface.surface2] {
                #expect(Self.contrast(color, surface) >= 4.5, "\(name) on \(String(surface, radix: 16))")
            }
        }
    }

    @Test
    func lightFilledControlsPassAA() {
        #expect(Self.contrast(Light.Semantic.primaryForeground, Light.Semantic.primary) >= 4.5)
        #expect(Self.contrast(Light.Text.onPositive, Light.State.positive) >= 4.5)
        #expect(Self.contrast(Light.Text.onExtra, Light.State.extra) >= 4.5)
        // The accent segmented control draws white on the accent.
        #expect(Self.contrast(0xFFFFFF, Light.Brand.accent) >= 4.5)
    }
}
