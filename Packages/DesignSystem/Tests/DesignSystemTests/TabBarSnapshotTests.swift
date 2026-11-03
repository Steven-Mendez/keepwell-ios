import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Tab bar snapshots")
@MainActor
struct TabBarSnapshotTests {
    @Test
    func homeSelected() {
        let bar = KWTabBar(
            items: [
                KWTabItem(id: 0, icon: .home, title: "Inicio"),
                KWTabItem(id: 1, icon: .list, title: "Movimientos"),
                KWTabItem(id: 2, icon: .tabAccounts, title: "Cuentas"),
                KWTabItem(id: 3, icon: .chartBars, title: "Resumen"),
            ],
            selection: .constant(0),
        )
        assertComponentSnapshot(of: VStack { Spacer()
            bar
        }, height: 84)
    }
}
