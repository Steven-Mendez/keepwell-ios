import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Toggle snapshots")
@MainActor
struct ToggleSnapshotTests {
    @Test
    func onOffAndPendingTint() {
        let view = VStack(spacing: KWSpacing.md) {
            Toggle("Respaldo en iCloud", isOn: .constant(true)).toggleStyle(.kw)
            Toggle("Ocultar montos al salir", isOn: .constant(false)).toggleStyle(.kw)
            Toggle("Es un gasto previsto", isOn: .constant(true)).toggleStyle(.kw(tint: KWColor.State.pending))
        }
        .font(KWTextStyle.body.font)
        .foregroundStyle(KWColor.Text.primary)
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 170)
    }
}
