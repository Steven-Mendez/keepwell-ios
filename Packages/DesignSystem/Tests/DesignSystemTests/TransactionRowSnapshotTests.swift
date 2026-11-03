import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Transaction row snapshots")
@MainActor
struct TransactionRowSnapshotTests {
    @Test
    func transactionRows() {
        let view = KWGroupedCard(horizontalPadding: 14, verticalPadding: 4) {
            KWTransactionRow(
                .planned,
                title: "Renta",
                subtitle: "Vivienda · Débito 1234",
                amount: "−C$3,500.00",
                secondaryAmount: "≈ $95.56",
            )
            KWTransactionRow(
                .expense,
                title: "Una descripción muy larga que no cabe en la fila",
                subtitle: "Restaurantes · Efectivo · nota larga",
                amount: "−C$250.00",
                secondaryAmount: "$6.83",
            )
            KWTransactionRow(
                .transfer,
                title: "Retiro",
                subtitle: "Ahorro → Efectivo",
                amount: "C$1,200.00",
                secondaryAmount: "$33.15 debitado",
            )
            KWTransactionRow(.income, title: "Intereses", subtitle: "Intereses · Ahorro", amount: "+$3.02", secondaryAmount: "C$110.61")
            KWTransactionRow(.planned, title: "Comida", subtitle: "Supermercado · Débito 1234") {
                Button("Confirmar") {}.buttonStyle(.kw(.primary, size: .mini))
            }
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 360)
    }
}
