import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Logo snapshots")
@MainActor
struct LogoSnapshotTests {
    @Test
    func markTileAndWordmark() {
        let view = VStack(spacing: KWSpacing.xl) {
            KWAppIconTile()
            KWWordmark()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KWColor.Brand.b700)
        assertComponentSnapshot(of: view, height: 240)
    }
}
