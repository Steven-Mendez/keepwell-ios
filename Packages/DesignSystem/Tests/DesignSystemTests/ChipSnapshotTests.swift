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
                KWChip("Todos", isSelected: true) {}
                KWChip("Gastos", isSelected: false) {}
                KWChip("Previstos", isSelected: false) {}
            }
            HStack(spacing: KWSpacing.xs) {
                KWChip("NIO · Córdoba", isSelected: true, style: .outlined, height: 38) {}
                KWChip("EUR · Euro", isSelected: false, style: .outlined, height: 38) {}
            }
            HStack(spacing: KWSpacing.xs) {
                KWChip("Supermercado", isSelected: true, style: .extra) {}
                KWChip("Compras", isSelected: false, style: .extra) {}
            }
        }
        .padding(KWLayout.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        assertComponentSnapshot(of: view, height: 180)
    }
}
