import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Chip snapshots")
@MainActor
struct ChipSnapshotTests {
    @Test
    func styles() {
        let view = VStack(alignment: .leading, spacing: KWSpacing.sm) {
            HStack(spacing: KWSpacing.xs) {
                KWChip("All", isSelected: true) {}
                KWChip("Expenses", isSelected: false) {}
                KWChip("Planned", isSelected: false) {}
            }
            HStack(spacing: KWSpacing.xs) {
                KWChip("NIO · Córdoba", isSelected: true, style: .outlined, height: 38) {}
                KWChip("EUR · Euro", isSelected: false, style: .outlined, height: 38) {}
            }
            HStack(spacing: KWSpacing.xs) {
                KWChip("Groceries", isSelected: true, style: .extra) {}
                KWChip("Shopping", isSelected: false, style: .extra) {}
            }
        }
        .padding(KWLayout.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        assertComponentSnapshot(of: view, height: 180)
    }
}
