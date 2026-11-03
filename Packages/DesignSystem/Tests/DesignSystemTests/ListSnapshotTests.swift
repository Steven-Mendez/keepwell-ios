import SwiftUI
import Testing
@testable import DesignSystem

@Suite("List snapshots")
@MainActor
struct ListSnapshotTests {
    @Test
    func groupedCardWithRowsAndHeaders() {
        let view = VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader("Moneda")
            KWGroupedCard {
                KWValueRow("Moneda principal", value: "USD · Dólar ›", style: .setting, verticalPadding: 14)
                KWValueRow("Categorías de gasto", value: "15 ›", style: .navigation, verticalPadding: 14)
            }
            KWSectionHeader("Plásticos", style: .large) {
                Text("+ Adicional").font(KWTextStyle.label.font).foregroundStyle(KWColor.Brand.link)
            }
            KWGroupedCard(verticalPadding: 4) {
                KWValueRow("Límite de crédito", value: "Sin definir", style: .placeholder)
                KWValueRow("Estado", value: "Confirmado", valueColor: KWColor.State.positive)
                KWTitleSubtitle("Efectivo", subtitle: "NIO · ya incluida").padding(.vertical, 14)
            }
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 400)
    }
}
