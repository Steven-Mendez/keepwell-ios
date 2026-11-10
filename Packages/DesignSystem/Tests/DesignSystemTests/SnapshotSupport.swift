import SnapshotTesting
import SwiftUI
@testable import DesignSystem

/// Renders a component on the app background at the design's 2× scale. Shared by every
/// snapshot suite so all references use the same device traits and tolerances. Dark by default,
/// the app's original look; light references pass `colorScheme: .light` and a `named:` suffix.
@MainActor
func assertComponentSnapshot(
    of view: some View,
    width: CGFloat = 390,
    height: CGFloat,
    named name: String? = nil,
    colorScheme: ColorScheme = .dark,
    fileID: StaticString = #file,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) {
    KWFonts.register()
    let framed = view
        .frame(width: width, height: height)
        .background(KWColor.Surface.bg)
        .environment(\.colorScheme, colorScheme)
    assertSnapshot(
        of: framed,
        as: .image(
            precision: 0.99,
            perceptualPrecision: 0.98,
            layout: .fixed(width: width, height: height),
            traits: UITraitCollection(displayScale: 2),
        ),
        named: name,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column,
    )
}
