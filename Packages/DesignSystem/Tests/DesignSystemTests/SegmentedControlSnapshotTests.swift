import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Segmented control snapshots")
@MainActor
struct SegmentedControlSnapshotTests {
    @Test
    func styles() {
        let view = VStack(spacing: KWSpacing.md) {
            KWSegmentedControl(
                [(value: 0, title: "Gasto"), (value: 1, title: "Ingreso"), (value: 2, title: "Transferir")],
                selection: .constant(0),
            )
            KWSegmentedControl([(value: 0, title: "Gastos"), (value: 1, title: "Ingresos")], selection: .constant(0), style: .compact)
            KWSegmentedControl([(value: 0, title: "NIO"), (value: 1, title: "USD")], selection: .constant(0), style: .accent)
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 200)
    }
}
