import SwiftUI
import Testing
@testable import DesignSystem

@Suite("FlowLayout snapshots")
@MainActor
struct FlowLayoutSnapshotTests {
    @Test
    func flowLayoutWrapsChips() {
        let view = KWFlowLayout {
            ForEach(["NIO · Córdoba", "MXN · Peso", "COP · Peso", "EUR · Euro", "Single currency", "Search…"], id: \.self) { title in
                KWChip(title, isSelected: title.hasPrefix("NIO"), style: .outlined, height: 38) {}
            }
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 120)
    }
}
