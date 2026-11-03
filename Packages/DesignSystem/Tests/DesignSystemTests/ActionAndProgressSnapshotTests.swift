import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Action and progress snapshots")
@MainActor
struct ActionAndProgressSnapshotTests {
    @Test
    func actionButtons() {
        let view = HStack(spacing: KWSpacing.xs) {
            KWActionButton("Pagar", icon: .arrowUp, style: .prominent) {}
            KWActionButton("Adicionales", icon: .addCard) {}
            KWActionButton("Descongelar", icon: .freeze, style: .active) {}
            KWActionButton("Gasto", icon: .plus, style: .translucent, captionSize: 13) {}
        }
        .padding(KWLayout.gutter)
        .background(KWColor.Brand.b900)
        assertComponentSnapshot(of: view, height: 110)
    }

    @Test
    func progressBars() {
        let view = VStack(spacing: KWSpacing.md) {
            KWProgressBar(0.54, fill: KWColor.State.extra)
            KWProgressBar(0.29, fill: KWColor.Brand.accent, height: 8)
            KWProgressBar(1.4, fill: KWColor.State.positive, height: 8)
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 100)
    }
}
