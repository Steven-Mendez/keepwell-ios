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
            KWLargeTitleHeader("Transactions") {
                KWCircleButton(.plus, style: .white, accessibilityLabel: "New transaction") {}
            }
            KWNavigationHeader("Mastercard ··1234", buttonStyle: .translucent) {}
            KWNavigationHeader("Family", subtitle: "Mastercard ··1234 additional", style: .leading) {}
            KWNavigationHeader("Settings", style: .large) {}
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 480)
    }
}
