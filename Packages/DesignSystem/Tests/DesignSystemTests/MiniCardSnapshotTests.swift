import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Mini card snapshots")
@MainActor
struct MiniCardSnapshotTests {
    @Test
    func miniCards() {
        let view = HStack(spacing: KWSpacing.sm) {
            KWMiniCard(.palette(.coral, chip: true))
            KWMiniCard(.palette(.lima, chip: true))
            KWMiniCard(.palette(.azul), size: .medium)
            KWMiniCard(.transfer)
            KWMiniCard(.add)
            KWMiniCard(.solid(KWColor.Brand.b500), size: .tiny)
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 80)
    }
}
