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
                [(value: 0, title: "Expense"), (value: 1, title: "Income"), (value: 2, title: "Transfer")],
                selection: .constant(0),
            )
            KWSegmentedControl([(value: 0, title: "Expenses"), (value: 1, title: "Income")], selection: .constant(0), style: .compact)
            KWSegmentedControl([(value: 0, title: "NIO"), (value: 1, title: "USD")], selection: .constant(0), style: .accent)
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 200)
    }
}
