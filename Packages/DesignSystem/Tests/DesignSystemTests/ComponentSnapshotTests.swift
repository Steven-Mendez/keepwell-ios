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
                Text("Net balance").kwTextStyle(.caption).foregroundStyle(KWColor.Text.muted)
                Text("$1,234.56").kwTextStyle(.amountLg).foregroundStyle(KWColor.Text.primary)
            }
        }
        .padding(KWLayout.gutter)

        // The shared helper paints the background over the whole 390×140 canvas; a width-only
        // frame left the edges to the host window, white or black depending on earlier tests.
        assertComponentSnapshot(of: view, height: 140)
    }
}
