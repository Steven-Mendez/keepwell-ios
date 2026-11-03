import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Header snapshots")
@MainActor
struct HeaderSnapshotTests {
    @Test
    func headers() {
        let view = VStack(spacing: KWSpacing.xl) {
            KWFlowHeader(.close, progress: (4, 1)) {}
            KWFlowHeader(.back, progress: (3, 2)) {}
            KWFlowHeader(.close) {}
            KWLargeTitleHeader("Movimientos") {
                KWCircleButton(.plus, style: .white, accessibilityLabel: "Nuevo movimiento") {}
            }
            KWNavigationHeader("Mastercard ··1234", buttonStyle: .translucent) {}
            KWNavigationHeader("Familiar", subtitle: "Adicional de Mastercard ··1234", style: .leading) {}
            KWNavigationHeader("Ajustes", style: .large) {}
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 480)
    }
}
