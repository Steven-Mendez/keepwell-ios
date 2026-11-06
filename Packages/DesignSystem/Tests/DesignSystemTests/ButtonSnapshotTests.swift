import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Button snapshots")
@MainActor
struct ButtonSnapshotTests {
    @Test
    func variantsAndSizes() {
        let view = VStack(spacing: KWSpacing.sm) {
            Button("Continue") {}.buttonStyle(.kw())
            Button("ATM withdrawal") {}.buttonStyle(.kw(.secondary))
            Button("Log another") {}.buttonStyle(.kw(.surface, size: .regular))
            Button("Delete account") {}.buttonStyle(.kw(.destructive, size: .row))
            Button("Complete card details") {}.buttonStyle(.kw(.link, size: .medium))
            Button("Not now") {}.buttonStyle(.kw(.plain, size: .text))
            HStack {
                Button("Back up now") {}.buttonStyle(.kw(.primary, size: .small))
                Button("Restore") {}.buttonStyle(.kw(.secondary, size: .small))
                Button("Confirm") {}.buttonStyle(.kw(.primary, size: .mini))
            }
            Button("Disabled") {}.buttonStyle(.kw()).disabled(true)
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 560)
    }
}
