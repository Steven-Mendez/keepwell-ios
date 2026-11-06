import SwiftUI
import Testing
@testable import DesignSystem

@Suite("List snapshots")
@MainActor
struct ListSnapshotTests {
    @Test
    func groupedCardWithRowsAndHeaders() {
        let view = VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader("Currency")
            KWGroupedCard {
                KWValueRow("Main currency", value: "USD · US dollar ›", style: .setting, verticalPadding: 14)
                KWValueRow("Expense categories", value: "15 ›", style: .navigation, verticalPadding: 14)
            }
            KWSectionHeader("Cards", style: .large) {
                Text("+ Add").font(KWTextStyle.label.font).foregroundStyle(KWColor.Brand.link)
            }
            KWGroupedCard(verticalPadding: 4) {
                KWValueRow("Credit limit", value: "Not set", style: .placeholder)
                KWValueRow("Status", value: "Confirmed", valueColor: KWColor.State.positive)
                KWTitleSubtitle("Cash", subtitle: "NIO · already included").padding(.vertical, 14)
            }
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 400)
    }
}
