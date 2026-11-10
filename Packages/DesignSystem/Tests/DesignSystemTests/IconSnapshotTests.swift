import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Icon snapshots")
@MainActor
struct IconSnapshotTests {
    @Test
    func allIcons() {
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 7), spacing: KWSpacing.md) {
            ForEach(KWIcon.allCases, id: \.self) { icon in
                KWIconView(icon, size: 24)
            }
        }
        .foregroundStyle(KWColor.Text.primary)
        assertComponentSnapshot(of: grid, height: 380)
    }
}
