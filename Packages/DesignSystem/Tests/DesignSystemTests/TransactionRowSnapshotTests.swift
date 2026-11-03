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
                title: "Rent",
                subtitle: "Housing · Debit 1234",
                amount: "−C$3,500.00",
                secondaryAmount: "≈ $95.56",
            )
            KWTransactionRow(
                .expense,
                title: "A very long description that does not fit in the row",
                subtitle: "Restaurants · Cash · long note",
                amount: "−C$250.00",
                secondaryAmount: "$6.83",
            )
            KWTransactionRow(
                .transfer,
                title: "Withdrawal",
                subtitle: "Savings → Cash",
                amount: "C$1,200.00",
                secondaryAmount: "$33.15 debited",
            )
            KWTransactionRow(.income, title: "Interest", subtitle: "Interest · Savings", amount: "+$3.02", secondaryAmount: "C$110.61")
            KWTransactionRow(.planned, title: "Food", subtitle: "Groceries · Debit 1234") {
                Button("Confirm") {}.buttonStyle(.kw(.primary, size: .mini))
            }
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 360)
    }
}
