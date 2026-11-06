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
                title: "No transactions yet",
                message: "Log your first expense, income or transfer and it shows up here.",
                actionTitle: "Log transaction",
            ) {}
            KWEmptyState(icon: .chartBars, title: "No data", message: "There is nothing to show yet.")
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 560)
    }
}
