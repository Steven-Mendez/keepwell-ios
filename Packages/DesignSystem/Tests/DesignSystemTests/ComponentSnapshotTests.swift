import SnapshotTesting
import SwiftUI
import Testing
@testable import DesignSystem

/// To re-record references run `make test-record-snapshots`
/// (or export `SNAPSHOT_TESTING_RECORD=all`) and commit the images under `__Snapshots__`.
@Suite("Component snapshots")
@MainActor
struct ComponentSnapshotTests {
    init() {
        KWFonts.register()
    }

    @Test
    func surfaceCard() {
        let view = KWSurfaceCard {
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                Text("Balance neto").kwTextStyle(.caption).foregroundStyle(KWColor.Text.muted)
                Text("$1,234.56").kwTextStyle(.amountLg).foregroundStyle(KWColor.Text.primary)
            }
        }
        .padding(KWLayout.gutter)
        .frame(width: 390)
        .background(KWColor.Surface.bg)
        .environment(\.colorScheme, .dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 390, height: 140),
                traits: UITraitCollection(displayScale: 2),
            ),
        )
    }
}
