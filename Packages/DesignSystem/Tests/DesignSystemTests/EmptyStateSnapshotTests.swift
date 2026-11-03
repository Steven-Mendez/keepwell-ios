import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Empty state snapshots")
@MainActor
struct EmptyStateSnapshotTests {
    @Test
    func withAndWithoutAction() {
        let view = VStack(spacing: KWSpacing.xxl) {
            KWEmptyState(
                icon: .list,
                title: "Aún no tienes movimientos",
                message: "Anota tu primer gasto, ingreso o transferencia y aparece aquí.",
                actionTitle: "Anotar movimiento",
            ) {}
            KWEmptyState(icon: .chartBars, title: "Sin datos", message: "Todavía no hay nada que mostrar.")
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 560)
    }
}
