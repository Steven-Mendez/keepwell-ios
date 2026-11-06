import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Background snapshots")
@MainActor
struct BackgroundSnapshotTests {
    @Test
    func glowBackgrounds() {
        let view = HStack(spacing: 0) {
            KWGlowBackground(.brand)
            KWGlowBackground(.success)
            KWGlowBackground(.navy)
            KWBrandGradient()
        }
        assertComponentSnapshot(of: view, height: 400)
    }
}
