import DesignSystem
import SnapshotTesting
import SwiftUI

/// Renders a whole screen at the design's 390×844 frame and 2× scale, dark mode.
@MainActor
public func assertScreenSnapshot(
    of view: some View,
    width: CGFloat = 390,
    height: CGFloat = 844,
    named name: String? = nil,
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
        .environment(\.colorScheme, .dark)
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
