import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Toggle snapshots")
@MainActor
struct ToggleSnapshotTests {
    @Test
    func onOffAndPendingTint() {
        let view = VStack(spacing: KWSpacing.md) {
            Toggle("iCloud backup", isOn: .constant(true)).toggleStyle(.kw)
            Toggle("Hide amounts on exit", isOn: .constant(false)).toggleStyle(.kw)
            Toggle("This is a planned expense", isOn: .constant(true)).toggleStyle(.kw(tint: KWColor.State.pending))
        }
        .font(KWTextStyle.body.font)
        .foregroundStyle(KWColor.Text.primary)
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 170)
    }
}
